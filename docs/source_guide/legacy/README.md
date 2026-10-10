# Hierarchy matmulfree: legacy notes

> **Category: LEGACY.**

[Project](<../../../README.md>) → [Documents](<../../README.md>) → **Hierarchy and data flow**

<details>
<summary>Page table of contents</summary>

- [How to read](#how-to-read)
- [1. Three things to grasp first](#1-three-things-to-grasp-beforehand)
- [2. Overview architecture diagram in operation](#2-the-currently-running-overall-architecture-diagram)
- [3. Number format and meaning of each width](#3-number-format-and-meaning-of-each-width)
- [4. From host start to HALT](#4-from-host-start-to-halt)
- [5. NORM + QUANT: why go through the vector three times?](#5-norm--quant-why-must-it-go-through-a-three-pass-vector)
- [6. TMATMUL: 32 PEs doing one dot product together](#6-tmatmul-32-pes-compute-one-dot-product-together)
- [7. Rowwise, sigmoid, and model state](#7-rowwise-sigmoid-and-model-state)
- [8. What is different compared to your thesis?](#8-how-is-it-different-from-your-thesis)
- [9. Signals to look at on the waveform](#9-signals-to-check-on-waveform)
- [10. Reading RTL syntax without confusing it with software code](#10-read-rtl-syntax-without-confusing-it-with-software-code)
- [11. Scope of verification in the document](#11-scope-of-document-verification)

</details>

This page describes **hierarchy legacy matmulfree** and includes diagrams/annotations matching the source on 06/10/2026.
The current full graph design is described at [full graph overview](<../full_graph.md>)
and [llm_soc architecture](<../../design/full_rtl_language.md>). The current catalog contains
[41 source/LUT assets](<../blocks/README.md>), with the hash status of each snapshot.

The code excerpts, line counts, and source hashes below belong to the snapshot recorded in
[source_manifest.json](<../source_manifest.json>). Schematics and code excerpts have been cross-checked with the current source. Read [verification status](<../../verification/optimization_status.md>) for
PASS/fail of the current source/config.

## How to read

1. Read sections 1–4 to understand the architecture, number format, and execution flow.
2. Read sections 5–7 to understand NORM + QUANT, ternary core, and rowwise unit.
3. Read section 8 to compare with the thesis.
4. Open the [RTL explanation index](<../blocks/README.md>) when you need to read each file. Each page has an overview, hardware architecture diagram, and source snippets grouped by **logical groups**. Each group keeps the original line range for reference, then explains the purpose, how data flows through the code, and the main signals. Complex logical groups include a hardware block diagram next to the explanation.

The annotation is a snapshot at the time of writing. The [source manifest](<../source_manifest.json>) records the SHA-256 and the number of lines to identify changes when the RTL is updated. Annotations are not inserted into synthesizing source.

## 1. Three things to grasp beforehand

**An instruction operates on vectors.** ADD does not just add two numbers; it requires the NPU to go through the elements of two tensors described by the descriptor. An instruction may take multiple cycles.

**32 PEs only refer to the ternary core.** In each computation batch, the core generates 32 ternary products and then adds them together for **one output**. It does not simultaneously produce 32 complete outputs. The rowwise unit has its own level of parallelism: ADD/SUB/MUL/RELU generates two elements per batch over five clocks; REC handles one element with two products over five clocks; SIG processes each element.

**Integer-only can still represent fractionals.** For example, raw S16 `0x0180` is 384; with `F_t=8`, the real value is `0x0180/0x0100=1,5`. The hardware stores integers and uses shift, multiply, rounding to handle scaling. This is fixed-point, not floating-point. Inference skips backpropagation but still needs to represent activation, gate, and state with fractionals.

### Number writing convention

Documents and RTL use hexadecimal for values directly attached to bit patterns, registers, addresses, masks, and fixed-point limits. For example: the largest S8 is `8'h7F`, the smallest S8 has raw `8'h80`, the largest S16 is `16'h7FFF`, and U16/F15 representing 1.0 is `16'h8000`. Decimal is still used for the number of elements, number of lanes, bus width, number of cycles, and loop indices because these quantities are easier to read in base 10. When a raw hexadecimal might cause confusion regarding the sign, the document includes the signed value in parentheses.

## 2. The currently running overall architecture diagram

![README — overview](../../diagrams/previews/73_README_1.svg)

[Editable draw.io — README — overview](../../diagrams/architecture.drawio) · Page `73_README_1`.

The boxes represent hardware blocks or interfaces; solid lines are data paths, dashed lines are control/configuration. Feedback arrows represent hardware connections. The diagram does not show cycle order, FSM states, or CPU pipeline stages.

Paths to the workspace go through the mux in `matmulfree`. `active_unit` selects rowwise, NORM, or TMATMUL. The scheduler allows only one instruction to operate at a time; the diagram does not imply that three units access SRAM simultaneously.

`matmul_wrap` only connects the core to the clock, reset, LED, and the host port of the existing wrapper. The name `CLOCK_50` is not the result of ASIC timing verification.

### What does the memory contain?

| Region | Logic capacity | Content |
|---|---:|---|
| Parameter SRAM | 1024 × 256 bit = 32 KiB | Ternary weight and bias S32 |
| Workspace SRAM | 256 × 256 bit = 8 KiB | Input, output, state, gate, and scratch of NORM |
| Instruction memory | 512 × 13 bit = 832 byte | Program loaded by host |
| Descriptor file | 8 × 32 bit + 8 × 96 bit = 128 byte | Metadata of address, size, format, and scale |

The above numbers are the logic data bits; they do not include control register, buffer, decoder, ECC, padding of macro, or physical area. Total data SRAM is 40 KiB. A 256-bit word contains 32 S8 elements, 16 S16/U16 elements, 8 S32 elements, or 128 ternary 2-bit weights.

`sram_256_wrapper` uses eight 32-bit banks and a single synchronous read port shared for host/compute. Data RAM and registers are not asynchronously reset; reset only clears control/tag. Simulation and synthesis use the same implementation, with no vendor-specific defines or attributes. Binding SRAM for ASIC requires a PDK adapter to maintain the read/valid contract and write mask; the logic bank structure does not specify a physical macro.

**Host read contract.** Top-level request + response with the tag: control/descriptor needs two rising edges, SRAM/imem requires four rising edges from the first sample request. Keep enable/read/address until ready and only take data when ready. Held request retains the first response; polling the new status at the same address requires idling for one clock edge. Changing address/dropping enable/write cancels the old read; write is still direct. Backend [SRAM adapter](<../blocks/sram_256_wrapper.sv.md>) and [instruction memory](<../blocks/ins_mem.sv.md>) still read/tag/valid for two rising edges; increased latency occurs at the top frontend. [Host interface](<../../design/legacy/interfaces.md#host-32-bit>) specifies the full rules.

## 3. Number format and meaning of each width

| Data/block | RTL format | Reason |
|---|---|---|
| Activation input to TMATMUL | S8 | Reduce storage and ternary addition width |
| Weight | 2 bit: `00=0`, `01=+1`, `11=−1` | `10` is an invalid code in the useful element |
| A ternary product | S9 | `−(−128 [0x80])=+128 [S9 0x080]` does not fit S8 |
| Dot product sum | S18 | Sufficient for K ≤ 512, including boundary `512×0x80=0x1_0000` |
| State, residual, candidate | S16; real value = raw × 2^(−F_t) | F_t per tensor, from 0 to 24; not fixed Q4.12 |
| Gate sigmoid | U16/F15; raw `0x0000…0x8000` | Representing 0…1, including exactly 1 |
| Bias | S32 per output unit | Added after rescale accumulator |
| Scale factor | M U24, r U6; factor ≈ M/2^r | No floating-point; real r domain uses 0…47 |
| Postscale product | RNE S42, add bias S43 | Preserve width before saturation to S16/S32 |
| Square in NORM | S32 signal, value always non-negative | Square S16 input |
| Sum of squares | U40 | Maximum `512×0x8000²=2^39` |
| Converted mean-square and epsilon | U64; addition checked with U65 | Avoid early fractional loss and detect overflow |
| Mean-square root | U32; remainder U34, trial subtract U35 | Integer root of U64, 32 steps taking each bit pair |
| Scratch z | S24/F16, sign-extend in S32 cell | Has fractional part for QUANT step; each SRAM word contains 8 z |
| Multiply z × QUANT coefficient | S48 | Rounding before clamping to S8 |
| Sigmoid interpolation | Coordinates S45, fraction U24, slope U10, product U34 | Maintain full S16 domain / F_t=0…24 and maximum slope 512 of LUT |

**RNE** is round-to-nearest-even: round to the nearest integer; if exactly halfway, choose the even number. For example 2.5 → 2; 3.5 → 4; −2.5 → −2. **Saturation** limits the result at the format boundary, instead of letting large positive numbers wrap into negative.

One should not understand "S64 appearing in the code" as the entire datapath being 64-bit wide, or "ternary" as the chip lacking a multiplier. The multiplier still serves NORM, scale, gate, and interpolation; only the multiplication of activation with ternary weight is replaced by sign/zero selection.

## 4. From host start to HALT

### 4.1 Descriptor instead of guessing tensor layout

Workspace descriptor 32 bit:

| Bit | Field | Interpretation |
|---|---|---|
| 31:24 | base_word | Address of the first 256-bit word in the workspace |
| 23:14 | length | Number of **elements**, not number of words |
| 13:12 | fmt | 0=S8, 1=S16, 2=U16, 3=S32 |
| 11:7 | frac_bits | F_t of the tensor; S8 after NORM uses its own dynamic scale metadata |
| 6:0 | reserved | Not used in the workspace descriptor |

Matrix descriptor 96 bit:

| Bit | Field | Interpretation |
|---|---|---|
| 95:86 | weight_base | First word of the weight matrix |
| 85:76 | bias_base | First word of the S32 bias |
| 75:66 | k_len | Number of input elements for a dot product |
| 65:56 | n_rows | Number of outputs |
| 55:32 | scale_m | M of the scale |
| 31:26 | scale_r | r of the scale |
| 25 | output_s32 | 0 writes S16; 1 writes S32 |
| 24:2 | reserved | Not used yet |
| 1 | no_bias | 1: use bias=0 and skip bias read |
| 0 | dynamic_q | 1: merge input scale generated by NORM into postscale |

K and the number of outputs of a command are maximum 512, but it also has to fit in memory. These two limits do not guarantee that every 512×512 matrix can fit into parameter SRAM.

### 4.2 Execution sequence

1. **Host load** weight, bias, input, initial state, descriptor, and program with HALT. Memory does not automatically contain valid data after reset.
2. **Host start** by writing bit 0 at `0x00040000`. Core clears the error status from the previous run and sets PC to 0.
3. **S_FETCH** waits for `instr_fetch_valid` then latches the 13-bit instruction into `instr_q`. Instruction memory reads synchronously and uses the same latency in all builds.
4. **S_START** decodes the opcode and selects the unit. For TMATMUL using dynamic scale, core checks q metadata then runs `scale_compose` first.
5. **S_WAIT** holds the current instruction and waits for the unit to signal `done`. The unit reads SRAM itself, computes, and writes the output.
6. **S_ADVANCE** increments the PC. No next instruction runs overlapping the instruction currently executing.
7. **S_HALT** outputs `running=0`, `ready=1`. The host checks for errors/overflow and then reads the output.

`ready=1` means the core has stopped and is ready for the host; it does not guarantee correct results on its own. Both `error` and `overflow_out` need to be read. Format errors halt the program; normal saturation writes the clamped result and maintains the overflow flag. NORM overflow causes a halt. If an error occurs after some of the output has been written, the RTL does not roll back the words that were written.

While running, the host is only allowed to perform control/status read transactions. The tensor currently in use must not be modified. PC=`9'h1FF` (511) and an instruction needing to proceed will cause an error, preventing the program from looping back to the beginning.

### 4.3 Instructions that are actually supported

| Opcode | Command | Data and behavior |
|---|---|---|
| `0x0` | NOP | Continue |
| `0x1`, `0x2` | ADD, SUB | Add/subtract two vectors with the same source scale, then convert to destination scale |
| `0x3` | MUL | S16×S16 or S16×gate; RNE and saturation |
| `0x6` | SIG | S16 → gate U16/F15 |
| `0x7` | NORM | RMSNorm without affine + QUANT: S16 → S8 |
| `0x8` | TMATMUL | S8×ternary → accumulator → scale+bias → S16/S32 |
| `0xB` | REC | Update state using gate and candidate |
| `0xC` | RELU | Set negative part to 0, rescale to destination |
| `0xF` | HALT | Stop program |

DIV, EXP, LDV, STV do not run in the current scheduler. `div.sv` still exists because NORM and scale_compose need to divide internal integers. The host replaces the data load/read role of LDV/STV at the current system level. SiLU can be composed from SIG and MUL, with the correct descriptor/scale.

## 5. NORM + QUANT: why must it go through a three-pass vector?

The purpose is to bring the S16 input to a normalized range, then quantize it to S8 for the ternary core. There is no learnable gamma/beta in this norm block; if the model has affine normalization, the export process must handle that part appropriately or add the operator.

Call the raw input x_i, the number of elements is K. With the scale input `s_x=2^(−F_t)`, the host needs to convert the actual epsilon into `epsilon_raw32 ≈ epsilon_real × 2^(2F_t+32)`. The core NORM receives the converted epsilon and does not read F_t by itself to perform this conversion.

### Round 1 — Calculate the common denominator of the entire vector

```text
S = Σ x_i²
Q = floor(S/K), rem = S mod K
V = (Q << 32) + floor((rem << 32)/K) + epsilon_raw32
R = floor(sqrt(V))
```

P1_CAPTURE latches operand, P1_MUL latches square, P1_PROC adds two squares into sum_sq. P2/P3 still latch the result at ROUND before PROC; total new overhead 8×ceil(K/2) clock/NORM. Padding elements outside K do not participate in the sum. Common divider U55/U32 computes quotient/remainder in 55 steps for each division. The largest numerator is bit 54 of `2^(32+r_norm)` with r_norm≤22; all mean-square divisions, fractional parts, and QUANT fit this range. `isqrt_u64` takes two radicand bits per step, uses remainder U34 and a subtraction U35 to both compare trial and update remainder; after 32 steps it returns root U32.

V holds 32-bit fractional part compared to mean-square calculated from raw input; therefore R approximately equals raw RMS multiplied by 65536. The next block selects M_norm/r_norm as per `M_norm/2^r_norm ≈ 2^32/R`.

### Round 2 — Create z and find the maximum amplitude

```text
z_raw[i] = RNE(x_i × M_norm / 2^r_norm)
z_real[i] ≈ z_raw[i] / 65536
A = max(abs(z_raw[i]))
D = max(A, delta_raw)
```

z has the format S24/F16 but occupies an S32 slot for simpler pack/unpack. At the same time, write to scratch, the core finds A. The scale quantization cannot be determined before knowing the largest element of the entire vector, so scratch needs to be kept.

All-zero input is handled separately with a norm factor of 0. `delta_raw` must not be 0 so that D is not 0. Scratch must not overlap input or output q. q is allowed to reuse region X because X has been fully read before round 3.

### Round 3 — Quantize z into q

```text
M_quant / 2^r_quant ≈ 0x7F / D
q[i] = clamp_S8(RNE(z_raw[i] × M_quant / 2^r_quant))
scale_q = D / (0x7F × 0x1_0000)
```

One output word contains 32 q. Keeping D is mandatory: q=64 can carry different real values between two vectors if D is different. Only transmitting 8-bit q and then discarding D will make TMATMUL scale incorrect.

`matmulfree` stores D according to the output descriptor, along with base/length. Eight tuples D/base/length have a total of 336-bit payload without async reset; only eight bits of `q_valid` reset to 0. Every place that reads a tuple is guarded by valid, and NORM completes successfully by writing all tuples at once while setting valid. Overwriting the q region invalidates metadata. The host writing the descriptor will clear the cache scale, so the descriptor needs to be loaded before running the NORM → TMATMUL sequence.

Epsilon is a shared control register. If the NORM operations require different converted epsilons, the host must split runs and update between runs, or the architecture needs to extend metadata. The current version should not be described as self-configuring epsilon separately for every layer.

## 6. TMATMUL: 32 PEs compute one dot product together

With an output j:

```text
acc[j] = Σ q[i] × w[j,i]
y_raw[j] = saturate(RNE(acc[j] × M / 2^r) + bias_raw[j])
```

Each PE reads one S8 q and one 2-bit weight. Weight +1 keeps q unchanged, −1 changes the sign of q, 0 sets q to zero. S9 can hold up to +128 (`9'h080`). The adder tree `acc_mul` combines 32 terms into `partial`; accumulator S18 sums partial results through the chunks.

**Example K=65:** requires `ceil(65/32)=3` chunk. The first chunk uses q[0…31], the second chunk q[32…63], the last chunk only q[64] is useful. The remaining 31 lanes are masked to 0. One row of weights needs `ceil(65/128)=1` 256-bit word; the core uses the 64-bit segments at offsets 0, 64, 128 of that word. Each new output row still starts at a new word boundary.

After the last chunk, the core reads bias if needed, runs postscale and packs output. S16 packs 16 outputs per word; S32 packs 8 outputs per word. The next row reuses the same 32 PEs. Output q must not overlap because q is still needed for subsequent rows.

### Where is the dynamic scale composed?

If q is loaded by the host with a known scale, the descriptor may already contain all coefficients `s_input × s_weight / s_output` and set dynamic_q=0.

If q is generated by NORM, dynamic_q=1 and M/r in the descriptor represents `s_weight/s_output`. `scale_compose` adds D:

```text
C_effective ≈ (M_descriptor / 2^r_descriptor) × D/(0x7F×0x1_0000)
```

The block selects r from 47 down using the exact RNE threshold before division, then runs at most one U48/U25 division in 48 steps to create M_effective U24/r_effective. Coefficients exceeding the range, D=0, or underflow to M=0 report an error. This is coefficient preparation according to tensor, not division for each PE. There is a separate divider in scale_compose and a U55/U32 divider in norm; the two blocks have not yet shared a physical instance.

TMATMUL is statically rejected if the extent input overlaps any q region that still has valid NORM metadata, even when using a different descriptor ID or only part of that region. Dynamic TMATMUL must select the correct ID that has stored metadata and precisely match base/length. The guard is placed before the ternary start, so these metadata errors do not write output.

### Does 32 PE mean 32 MACs per clock?

There are 32 parallel ternary terms in the ACCUM step, but the FSM also has request, wait, bias, scale, and write steps. Therefore, `32 × frequency` cannot be taken as the sustained throughput of this RTL. The number of cycles also depends on K, the number of outputs, memory latency, and other operators. It is also not a two-dimensional systolic array. A systolic array is not necessary to function correctly with a small model; increasing throughput requires considering both bandwidth and buffer.

## 7. Rowwise, sigmoid, and model state

`rowwise_dispatch` splits the vector into words containing up to 16 elements, reads A then B when necessary, calls `rowwise_op`, waits for done, and writes the result. The datapath has separated LOAD/MULTIPLY/RAW/ROUND/PACK using registers; handshake and descriptor contract remain unchanged. SIG and RELU only need A. REC also reads the current destination as the old state H.

ADD/SUB keeps an extension bit before changing scale. MUL uses two 16×16 multiplications for two elements. REC uses those same two multiplications for **one** element:

```text
new_H = sat_S16(RNE((F_raw × old_H + (0x8000−F_raw) × C) / 0x8000))
```

F is gate U16/F15; H and C must have the same scale. The two products are summed in S33 and then sent to lane 0 of the two scale/RNE paths shared with ADD/SUB/MUL/RELU, fixed shift 15; lane 1 does not record the REC state. Only round the sum once. For example, H=C=`0x0001` raw and F_raw=`0x4000`: the correct result is `0x0001` raw. If the two products 0.5 are rounded separately according to RNE and then added, the result will be 0; that is not the current REC behavior.

### How is Sigmoid using LUT?

The ROM has 257 samples, at `x_i=−8+i/16`, i=0…256. The samples are quantized according to:

```text
LUT[i] = RNE(0x8000 / (1 + exp(−x_i)))
```

This is the **table generation formula before running**, not the hardware for calculating exp during inference. The ROM in `sigmoid_lut.svh` is a constant case table. `sigmoid_257.mem` contains the same hex pattern for simulation checks. The LUT `sigContent.mif` from the old design has been removed from the main source; it only exists in historical documents.

With x between two samples, the core reads y0 and y1 via a ROM address used in turn, then interpolates. S45 coordinates cover the entire input range; the slope `y1−y0` is U10 because the table is monotonic and the maximum sample difference is 512, the slope×fraction product U24 equals U34. RNE still applies to the total interpolation sum to maintain correct parity when tied. x=0 corresponds to raw=`0x4000`, i.e., gate=0.5. Outside the range [−8,8], the core uses boundary samples `0x000B` and `0x7FF5`; it does not return exactly `0x0000`/`0x8000` at these boundaries.

RTL uses a constant case table for both simulation and synthesis, there is no loader file, and no LUT path parameter or tool-specific branch. The generator/test compares the two LUT assets and reports an error if missing or corrupted. The ROM logic still requires the target synthesis flow to know the physical mapping; it is not yet a bound ROM macro.

### A single inference pass using a small MLGRU

A suitable program can normalize the input, compute ternary projections for gates/candidates, use SIG/SiLU, run REC to update the state, and then compute the output projection. The host takes the logits and chooses the next token. This is a description of how to map it, not a statement that every MLGRU model has been exported or end-to-end tested.

To create a sentence generation demo, you also need a properly trained model, a tokenizer or character table, an exporter pack of weight/scale, an instruction program, and to check the output against a reference model. Ternary weights do not automatically guarantee that all other operators are supported by the NPU. The quality of the chatbot also depends on the model and training data, not just the PE count.

## 8. How is it different from your thesis?

The comparison source is [DTUT-242-13.pdf](<../../history/references/DTUT-242-13.pdf>), chapter 4 and the testcase section of chapter 5. The “thesis page” below refers to the number printed in the footer; the PDF page number is greater than 11. For example, Figure 4 on thesis page 31 corresponds to PDF page 42. The table distinguishes **description in the thesis** from **current RTL behavior**, without taking measurements from the old design and assigning them to the new design.

| Content | Design described in thesis | Current RTL ASIC | Consequence |
|---|---|---|---|
| Control | Pipeline Fetch → Decode → Execute → Memory → Write Back; Figure 4, pages 30–32 | Single-issue FSM in matmulfree | More compact control; not much instruction overlap |
| Hazard handling | Stall/flow control according to dependency, TMATMUL, FIFO; page 49 | Wait done before next instruction; check descriptor and memory overlap | Do not use hazard_detect or old pipeline register in current top |
| Instruction | 13 bits, normal vector 512 elements; pages 32–34 | Keep 13 bits; ID points to descriptor; K=1…512 | Tensors have variable length, handle tail |
| Payload memory | 512-bit word; pages 36, 45 | 256-bit word | Half the width of each word; element capacity depends on format |
| Activation | 16-bit fixed-point in ALU; pages 43–44 | S8 for TMATMUL, S16 for state/rowwise, U16/F15 for gate | Format depends on role; no single Q-format applied across the chip |
| Rowwise parallelism | 32 element-wise operations per clock as described on page 44 | Two elements per ADD/SUB/MUL/RELU step; one REC; sequential SIG | Prioritize small resources; actual throughput must be measured |
| Weight ternary | Ternary already used and addition/subtraction instead of multiplication; chapters 3 and 4.4 | Still ternary; 2-bit explicit code, reserved code signals error | Ternary is not a new feature of v2 |
| NORM | Square → reduction → sqrt/div; pages 44–45 | Three passes over the entire K, generate q S8 and D to maintain scale | NORM + QUANT path and scale are explicitly connected |
| Sigmoid | LUT sigContent.mif in the lanes; page 44 | A 257-sample ROM used sequentially and interpolated | Reduce table repetition; trade off latency and approximate error |
| EXP/DIV vector | Present in ISA thesis, pages 32–33 and 43 | Opcode rejected; scalar divider still used internally | Old programs do not run as-is |
| REC, RELU | Not in ISA table pages 32–33 | Opcodes B and C | REC combines two multiplications and rounds once |
| Memory model | Mapping vector/matrix, FIFO-style, DDR3; pages 45–49 | Parameter 32 KiB + workspace 8 KiB; host loads when idle | No DMA/DDR streaming in the current path |
| Write-back | Wb mux and pipeline register; page 32 | Each unit writes workspace through mux | No separate WB stage in the scheduler |
| Implementation target | FPGA; part of thesis results | RTL aimed at small ASIC | Requires SRAM macros, synthesis, timing, DFT, and physical design to become an ASIC |

The thesis mentions 16-bit fixed-point in the ALU section; the table above does not automatically assign the Q4.12 name to every block if the corresponding thesis section does not specify the decimal point position. It is necessary to distinguish the format in the historical source from the statement in the thesis.

### Results not directly transferred from the thesis to v2

Thesis page 61 (PDF 72) reports 70,383 cycles for the ternary testcase and 790,934 cycles for baseline normal multiplication. Those are **testcase** numbers in the thesis, not benchmarks of the current source. V2 changes memory width, number of lanes, normalization, scheduler, and LUT; to compare speed, the same workload, same precision, same clock, and re-measurement are needed.

The thesis describes a 19-bit memory pointer on page 48. The logical address width is not sufficient to conclude that a new ASIC has that much physical SRAM. Similarly, FPGA resource specifications or power in the thesis should not be used to infer the area/power of v2 ASIC.

### How has the orientation/direction changed?

The thesis prioritizes a processor structure with a pipeline and parallelism for large vector testcases. The current version prioritizes a small inference path, clearly defined arithmetic, limited memory, and easily verifiable instruction-by-instruction processing. The new approach trades parallelism for resources and simplicity. It has not yet demonstrated how much faster, smaller, or whether it can run a complete conversational model.

## 9. Signals to check on waveform

| When you want to know… | Check signal |
|---|---|
| Which instruction the core is at | pc_debug, instr_debug, sched, active_unit |
| Whether the instruction has finished | running, ready, row_done/norm_done/tm_done |
| Whether SRAM has valid data | ws_rd_en, ws_rd_addr, ws_rd_valid, ws_rd_data |
| Which part is TMATMUL computing | output_row_q, input_chunk_q, partial, accumulator_q |
| At which step is NORM wrong | state, sum_sq, v_raw, rms_r, absmax, quant_d |
| Does Scale follow q or not | q_valid, q_d, input_has_runtime_scale, selected_quant_d, composed_m, composed_r |
| Is Gate/state incorrectly formatted | format_error, gate, recurrent_sum, recurrent_value |
| Is the result clamped or is the program erroneous | overflow_out and error, check each flag separately |

Read FSM according to REQ/WAIT pairs: REQ issues the request; WAIT waits for valid; PROC/ACCUM only uses the confirmed data. The mark `<=` is a nonblocking assignment: all registers on the same clock edge use the old value on the right-hand side. Therefore, it does not read a sequence `<=` like sequentially running software instructions.

## 10. Read RTL syntax without confusing it with software code

| Syntax | How to read in this design |
|---|---|
| `logic [255:0] word` | A 256-bit vector; not 256 independent integers |
| `logic signed [15:0] x` | A signed 16-bit number in two's complement; decimal point position is determined by a separate scale |
| `word[i*16 +: 16]` | Take 16 consecutive bits, starting at bit i×16; i=0 is the element in the lowest bits |
| `{a,b}` | Concatenate bit a at the high side and b at the low side |
| `{{8{z[23]}},z}` | Repeat the sign bit of z eight times to extend S24 to S32 while preserving the value |
| `$signed(x)` | Interpret the bits of x as signed; the cast itself does not add bits to prevent overflow |
| `a ? b : c` | Mux: select b when a is true, otherwise select c |
| `always_comb` | Combinational logic; changing the input can change the output without waiting for a clock edge |
| `always_ff @(posedge clk ...)` | Register updates on the rising edge of the clock; reset in the sensitivity list can be asynchronous |
| `x <= y` | In a clocked process, latch y to x using nonblocking assignment; in comparison conditions, the same symbol means "less than or equal to" |
| `for (...)` | Depending on the location, it can describe multiple parallel logic; does not inherently carry meaning, each cycle consumes a cycle |
| `.port(signal)` | Connect the port with the child module's name to the signal in the parent module |
| `parameter` / `localparam` | Configuration or constant at elaboration, not a control register that the host can write |

For example, two lines `q_word <= ws_rd_data; state <= ACCUM;` run at the same clock edge: the buffer accepts the new word and the FSM transitions simultaneously. The logic in the ACCUM step then computes on the latched word. This is why the blocks separately distinguish WAIT and PROC/ACCUM.

## 11. Scope of document verification

Reference document for 37 files `.sv/.v` and four LUT assets (`sigmoid_lut.svh`, `sigmoid_257.mem`, `llm_exp_lut.svh`, `llm_gumbel_lut.svh`). Each RTL page is extracted verbatim from the source according to logic groups, recording the line number and SHA-256. Legacy modules are still used by regression with separate pages; some files have no meaningful blocks instantiated in the current top. Original PDF/PPT thesis/papers are kept as historical documents.

The manifest currently covers 41 RTL/LUT assets, 157 logic groups, and 5,262 lines of RTL source. Current render metrics and link checks are in [validation.json](<../validation.json>) and [diagram_validation.json](<../diagram_validation.json>). Packages have explanatory diagrams but are not module instances in the hierarchy. Rerun `python docs/source_guide/validate.py` after modifying the source or diagrams.

Unified RTL regression on 01/10/2026 at 14:31:18 passed **10 items**, compile **0 errors, 0 warnings**: ROM asset check; **168 host cases/23,827 commands** (NORM 43, ternary 65, rowwise 57, host/PC 3); 106 division, **4,301 sqrt**, 37,189 RNE, **900 coefficient cases** with up to 99 observable clocks; 5 divider profiles; **12,720 postscale checks**; 1,027 instruction memory checks; **1,638,400 sigmoid inputs across all 25 F_t=0…24**; 3,242 addsub, 4,452 mul, 5 accumulator profiles; 47 SRAM checks; **1,800 ca rowwise / 13,260 elements**, reference S128, 42,843 input changes when busy and six-phase reset. Host frontend added **30 protocol reads, 11 cancellations, 4 blocked regions**. The new cases tested TRA rejected NORM after overflow does not reset, static TM via descriptor alias/subrange, reset metadata and restart, divider with NUM_W=1 or DEN_W>NUM_W, busy/start protocol and reset between transactions. Testbench checks arbitration and generator/test rejects two missing assets, two broken assets. RTL has no assertions or file I/O; these checks are in verification. Hash/result at [tests/results.json](<../../../tests/results.json>); rerun with `./tests/run.ps1 -Block All`, no macro or separate build mode needed.

Quartus Analysis & Synthesis demo on 01/10/2026 at 11:24:04 pass **0 error, 0 warning**: **6,497 registers**, **11,798 ALUT**, **8,005 estimated ALM**, 334,336 bit block RAM, 7 DSP. Compared to the previous portable snapshot before this review round: 6,712→6,497 registers and 8,441→8,005 estimated ALM; RAM/DSP unchanged. This is a compile illustrating RTL synthesis capability; FPGA figures are not architecture or ASIC PPA constraints. This is an A&S snapshot before timing optimization. [Timing hub](<../../verification/timing/README.md>) records FPGA Fitter/STA, constraints, and critical path; ASIC STA not yet available. See [report and warnings](<../../verification/README.md>), [full design review](<../../history/reviews/design_review.md>).

RTL and verification use the same memory/ROM behavior. [Demo checkpoint Binary-MNIST160](<../../demos/legacy/mnist.md>) has run end-to-end on 10 sample images, comparing 40 layer passes and two full-graph program executions; RTL was not changed. There is no SRAM PDK binding, ASIC PPA, or full MNIST/model language accuracy yet. Sharing the chip-wide multiplier and exporter for other graphs still needs implementation.


[Demo MNIST](<../../demos/legacy/mnist.md>) runs the graph on RTL; [NanoFable hybrid legacy](<../../demos/legacy/nanofable_hybrid.md>) runs generation on CPU and replays 168 linear ternary operations on RTL. Each report records a reference, source/asset hashes, and separate limits.

---

[Read more: each RTL module](<../blocks/README.md>) · [Verification](<../../verification/README.md>) · [Back to document index](<../../README.md>)
