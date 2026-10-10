# ISA, descriptor, and host interface

<!-- reading-navigation:start -->
[Documentation](../../README.md) → [Archive](../../archive/README.md) → This page

| Reading guide | Document |
|---|---|
| New to the subject | [NPU and RTL fundamentals](../../00-start-here/fundamentals.md) · [Glossary](../../00-start-here/glossary.md) |
| Read first | [Legacy architecture](architecture.md) |
| Continue / related lookup | [Current evidence](../../verification/optimization_status.md) |
<!-- reading-navigation:end -->

> **Category: LEGACY.**

> **Legacy scope:** this page describes the matmulfree core.
> The current top llm_soc has [architecture](<../full_rtl_language.md>) and
> [host interface](<../host_interface.md>) separately.

This page describes the ISA/host of the instruction-driven legacy core. Host map and
parameter/config/prompt contract of the current top `llm_soc` are located at
[full RTL language graph](<../full_rtl_language.md>).

<details>
<summary>Page table of contents</summary>

- [Currently executing configuration](#current-configuration-being-executed)
- [13-bit Instruction](#13-bit-instruction)
- [Dynamic Descriptor and scale](#descriptor-and-dynamic-scale)
- [32-bit Host](#host-32-bit)
- [LUT](#lut)
- [Build and regression](#build-and-regression)
- [RTL organization and changes to support ASIC](#rtl-organization-and-changes-to-support-asic)
- [Current ASIC deployment limits](#current-asic-implementation-limits)

</details>

RTL and documentation updated on 01/10/2026. The main source uses a single implementation for simulation and synthesis; do not select datapath according to `SYNTHESIS`, `QUARTUS_SYNTHESIS`, or Quartus-specific memory attributes. Quartus is used to demo Analysis & Synthesis and FPGA timing. RTL uses integers for inference; timing/PPA or ASIC SRAM binding have not been confirmed. See [review and verification report](<../../history/reviews/design_review.md>), [critical path/Fmax](<../../verification/timing/README.md>), [overview and block diagram](<../../source_guide/legacy/README.md>), and [file annotations](<../../source_guide/blocks/README.md>).

`Verilog Source code` is the source currently under development. The `npu_asic_v2` copy was removed when cleaning the workspace; necessary tests have been merged into `tests`.

## Current configuration being executed

- Ternary core 32 PE, processing one output row at a time; activation S8, weight 2 bit, accumulator S18, K=1…512.
- Weight code `00=0`, `01=+1`, `11=−1`. Code `10` in the useful data section acts as an error instruction; padding outside K is ignored.
- State/residual/embedding S16 with scale `2^(-F_t)`, F_t=0…24; gate U16/F15 with raw value `0x0000…0x8000`.
- NORM shares two multipliers S25×S25 and two RNE paths across three passes; ternary weight address uses pointer/stride. See [review and optimization data](<../../history/reviews/design_review.md>).
- Scalar: sqrt radix-4 32 steps; NORM uses divider numerator U55; compose has fit filter RNE before divider U48/U25, maximum one division. Rowwise uses shared two scale/RNE paths for ADD/SUB/MUL/RELU/REC.
- NORM + QUANT process entire vector: squaring U32, sum U40, mean-square/epsilon U64, square root U32, scratch S24/F16 in S32 cell, output S8.
- SRAM logic: parameter 1024×256 = 32 KiB; workspace 256×256 = 8 KiB. Instruction memory 512×13 bit counted separately.
- Scheduler single-issue, waits for each multi-cycle instruction to complete. Does not use pipeline v1 to control datapath v2.
- Both K and the number of outputs of an instruction are limited to a maximum of 512. Larger vocabularies require extended configuration/control; this version does not yet have on-chip streaming argmax.

S/U means signed/unsigned; signed bit already includes the sign bit. F15/F16 indicates the bit of the fractional part, not floating-point. NPU does not have FP16/BF16/FP32 datapath.

## 13-bit Instruction

`[12:9]=opcode`, `[8:6]=dst descriptor`, `[5:3]=src1/matrix descriptor`, `[2:0]=src0 descriptor`.

| Opcode | Instruction | Behavior |
|---|---|---|
| `0x0` | NOP | Move to the next instruction |
| `0x1` / `0x2` | ADD / SUB | Both sources have the same scale; rescale to destination scale, RNE and saturation. Supports S16; gate U16/F15 uses the same format for all three descriptors |
| `0x3` | MUL | S16×S16 or S16×gate U16/F15; supports both left and right shift according to the destination scale |
| `0x6` | SIG | S16→U16/F15 via LUT and interpolation |
| `0x7` | NORM | RMSNorm without affine + QUANT; S16→S8, keep dynamic scale metadata |
| `0x8` | TMATMUL | S8×ternary→ACC18→postscale+bias→S16/S32 |
| `0xB` | REC | Read `dst` as old state H, `src0` as candidate C, `src1` as gate F. Write `RNE((F*H+(0x8000-F)*C)/0x8000)` to dst; H and C with the same scale. Two products are summed before rounding |
| `0xC` | RELU | S16→S16, clamp negative numbers to 0 then rescale according to the destination descriptor |
| `0xF` | HALT | End of program |

DIV, EXP, LDV, and STV are not supported by the scheduler; when encountering these opcodes, stop and set an error. The scalar divider can still be used internally. SiLU can run using SIG followed by MUL. The host performs argmax/tokenization if the application requires it. Every program must end with HALT; passing through the last instruction without HALT will report an error instead of looping the PC.

ADD/SUB/MUL/SIG/RELU support in-place operation when the bases are the same and the format/length is valid. Partial overlap is rejected. REC allows candidates to share the state, but the gate cannot be overwritten by the state. NORM allows q to share the X region after completing the scratch creation pass; scratch cannot overlap X or q. TMATMUL does not allow output to overlap with q.

## Descriptor and dynamic scale

Workspace descriptor 32 bit retains layout: base `[31:24]`, length `[23:14]`, format `[13:12]` (`0x0=S8`, `0x1=S16`, `0x2=U16`, `0x3=S32`), F_t `[11:7]`, reserved `[6:0]`.

Matrix descriptor 96 bit retains layout: weight base `[95:86]`, bias base `[85:76]`, K `[75:66]`, output count `[65:56]`, M `[55:32]`, r `[31:26]`, output S32 flag `[25]`. The two previously reserved bits have new meanings:

- **Bit 0 = dynamic_q:** M/r description `s_weight/s_output`. After NORM, hardware generates postscale coefficient `C ≈ (M/2^r) × D/(127× 65536)` and selects new U24/U6 pair using RNE. Each workspace descriptor stores a separate D. D is max(abs(z), delta).
- **Bit 1 = no_bias:** skip reading bias from SRAM and use bias=0.

When dynamic_q=0, M/r has already included all `s_input*s_weight/s_output` coefficients, used for q preloaded by the host. Static TM scale rejects any input region overlapping with q generated by NORM while the metadata is valid, even if the descriptor ID is different or partially overlapping. Dynamic TM requires metadata of the correct ID, base, and length. Overwriting the q region invalidates the corresponding scale. Writing the descriptor via host clears the entire scale cache; therefore, all descriptors should be loaded before running the program.

Bias S32 is always calculated in output units and added **after** rescale. r ranges from 0…47. Coefficients that cannot be represented in U24/U6 are rejected and bits are not automatically truncated. S8 scale after NORM is dynamic scale D/(127×65536), and is not taken from the F_t field of the S8 descriptor.

## Host 32 bit

The address is a byte address and must be divisible by 4. The host loads each 32-bit slice, low lane first. Windows do not alias to addresses outside the range.

| Address | Content |
|---|---|
| 0x00000000…0x00007FFC | Parameter SRAM |
| 0x00010000…0x00011FFC | Workspace SRAM |
| 0x00020000 + 16×ID | Workspace descriptor ID=0…7 |
| 0x00020100 + 16×ID + 4×word | Matrix descriptor; word=0,1,2 in the order low bits first |
| 0x00030000…0x000307FC | Instruction memory; 13 low bits per host word |
| 0x00040000 | Write bit0=1 to start at PC=0; read `[3:0]={error,overflow,ready,running}` |
| 0x00040004 | Current PC |
| 0x00040010 | Base scratch z, default `0x80` |
| 0x00040014 / 0x00040018 | epsilon_raw32, low/high 32 bits |
| 0x0004001C | raw delta U24, required ≥1 |
| 0x00040020 / 0x00040024 | Nearest QUANT / NORM factor, `{2'b0,r[5:0],M[23:0]}` |
| 0x00040028 | D of nearest NORM + QUANT |

While running, only read control/status is accepted. Other accesses or invalid addresses have host_ready=0 and do not modify memory. This is a simple host window, not yet an AXI/APB bridge. Normal saturation sets overflow; format, address, factor, or opcode errors set error and stop the scheduler. Output already written in previous words before detecting data error is not rolled back.

The host holds `host_en=1`, `host_we=0`, and the stable address up to `host_ready=1`, then fetches `host_rdata`. Top latch request and response with the tag: control/descriptor read require **two rising edges**, parameter/workspace SRAM and instruction read require **four rising edges** counted from the first sample request. The host write is still directly acknowledged when valid and committed at the clock edge. Address change requests, lowering enable, or switching to write cancel the old read; only control/status reads are allowed when running.

After ready, if the same enable/address is kept, the first response is held in the transaction cache. To poll the new status at the same address, lower `host_en` at least one rising edge and request again, or change the address/issue write. Data only becomes meaningful when ready. Reset clears valid requests/responses, masks outputs to zero, and retains RAM content.

Backend SRAM/instruction adapter still uses read/tag/valid on both edges; two register boundaries at frontend top introduce new host latency. Scheduler fetch remains unchanged: waits for valid instruction, adding two cycles per instruction compared to the old combined fetch model.

`epsilon_raw32` is a shared register. If NORMs have different F_t or epsilon, the exporter/host must schedule updates to this register between program segments; there is no separate epsilon in the descriptor yet.

## LUT

`sigmoid_257.mem` contains 257 samples of `RNE(0x8000*sigmoid(-8+i/16))`. The original samples were correct; the fixed errors were in coordinate conversion and RNE during interpolation.

- First/last samples: `0x000B`/`0x7FF5`; middle sample: `0x4000`. Values outside [-8,8] are clamped to the two boundary samples.
- `sigmoid_lut.svh` contains the same data in the default ROM format, so runtime does not depend on the working directory.
- ROM always uses the `case` table as a constant in `sigmoid_lut.svh`, with a shared read address for two consecutive samples; `initial`, `$readmemh` or loading files at runtime are not needed.
- Interpolation uses S45 coordinates and 24-bit fractional part to maintain accuracy for all S16 inputs with F_t=0…24. The difference between two consecutive samples does not exceed 512, using U10 and the product U10×U24→U34. RNE applies to the entire interpolated values, including the parity of the first sample. Tooling checks the slope limits when generating/matching the ROM.
- There are no parameters `LUT_FILE`/`SIG_LUT_FILE`. Replace the LUT by regenerating the constant table and checking all 257 samples against the reference before building.
- LUT Q4.12 and the old files `.bak` have been removed because they do not participate in the current datapath. `sigmoid_lut.svh` is ROM data in RTL; `sigmoid_257.mem` keeps the same patterns for comparison and generation.

Recreate/check ROM: `python tests/reference.py --rtl "Verilog Source code" --check`.

## Build and regression

The repository contains RTL, documentation, runner/reference/testbench, and a lightweight fixture to rerun. Runtime, checkpoint download, and build cache are created locally. Prepare ModelSim according to the [test instructions](<../../../tests/README.md>); the commands below run from the root directory of the repository.

Run from the root directory of the repository:

```powershell
./tests/run.ps1 -Block All
```

Script using ModelSim at `C:/intelFPGA/20.1/modelsim_ase/win32aloem`, compile the package before the module, set the include path for the LUT, and compare bit-exact with the integer Python reference. You can change `-SimBin` in `tests/run.ps1`. Log is located at `tests/sim/`; results and source hash are at `tests/results.json`. Select each block using `-Block Host`, `Norm`, `Ternary`, `Rowwise`, `Scalar`, `DivProfiles`, `Postscale`, `Sigmoid`, `Imem`, `Sram`, `Arithmetic`, `AccMul`, `AddSub` or `Mul`; there are no more `-Mode` parameters.

Regression runs a unified RTL set. The module `tb_sram` in `tests/tb_all.sv` checks latency, consecutively changes the host address, masks writing for each lane, computes reads, and resets to hold SRAM data. Misuse/handshake checks are located in the testbench instead of changing the RTL according to macro synthesis. After regression, Analysis & Synthesis can be run using Ctrl+K in the Quartus project to check synthesize capability.

The `All` round after reviewing the entire design passed **10 check items** at 14:31:18 on 01/10/2026: ROM and nine RTL testbenches; compile 0 error/0 warning. Includes 168 host cases along with 30 protocol reads/11 cancellations/4 blocked regions, 900 exact compose, 4.301 sqrt, 12.720 postscale and 1.638.400 sigmoid inputs across all 25 F_t. Rowwise adds 1.800 cases with reference S128, checking busy-input changes and reset during phases. A&S after timing optimization passed 0 error/0 warning at 14:31:44; see [timing report](<../../verification/timing/README.md>) and [design review](<../../history/reviews/design_review.md>).

Check dedicated hardware reasoning: `quartus_sh -t tests/check_synthesis.tcl`. Script for checking latch/RAM in Quartus demo netlist. SRAM is divided into eight 32-bit banks with separate write-enable in every build; the descriptor uses a 32-bit register with a fixed index for each word. This way of writing clearly describes enable/reset to the synthesis tool, without requiring Intel primitives or attributes.

`matmul_wrap` keeps CLOCK_50/SW/LEDG and adds host ports. LED0=ready, LED1=overflow, LED2=error. Board pin assignment must add host ports if using this wrapper.

The pipeline registers, ctrl_unit, hazard_detect, and mem_burst are not instantiated by the current top and have been removed during cleanup; check historical code via Git/evidence archives. The v1 regressions using the old interface have been removed; the current test is in a file `tests/tb_all.sv`.

## RTL organization and changes to support ASIC

- State machines and assignments have been split across lines; register names like `source_a_q`, `input_desc_q`, `vector_length_q` describe the data held through cycles. Opcode names are used instead of direct numbers in the vector unit.
- `rowwise_op` shares **two unsigned 16×16 multiplications** for MUL and REC using a operand mux, then recovers the sign. When not in use, the multiplier operand is held at 0 to reduce switching. This is sharing in the vector unit; other engines still have their own separate multipliers.
- `regfile` and `mem_mapping` share `sram_256_wrapper`: one 8×32-bit masked write port and one synchronous read port shared between host/compute. The memory array and data registers being read do not have asynchronous reset; the tag/control is reset, while the RAM content is preserved.
- The wrapper is a common RTL adapter to be replaced by an SRAM macro. When binding the macro, the adapter must maintain arbitration, current write mask, and read-valid; if latency/macro ports differ, the adapter needs adjustment and handshake verification. The core does not instantiate FPGA primitives or attach `ramstyle`/`M10K`.
- Cache scale only resets q_valid; 336 payload bits use full write, separate enable, and fixed index for each slot, all consumers gated by valid.
- Regression checks one implementation. Quartus report at `docs/verification/reports/quartus_synthesis.rpt` only illustrates synthesis capability and FPGA mapping of the corresponding snapshot; it does not verify Fitter, STA, or ASIC PPA.

## Current ASIC implementation limits

Simulating confirmation of arithmetic functionality and communication in the executed cases. [Demo checkpoint Binary-MNIST160](<../../demos/legacy/mnist.md>) passes 10/10 sample images, 40 bit-exact layer iterations, and two consecutive graph runs, keeping RTL unchanged. [Demo NanoFable](<../../demos/language.md>) runs 3 prompts × 32 tokens on CPU and replays 168 iterations of actual linear ternary on RTL, matching 33,792 S32 outputs. Text generation for the entire graph and unsupported operators still run on CPU; the whole model has not yet run on core. No evaluation of the entire MNIST, synthesis/ASIC STA, area/power, DFT, or PDK SRAM binding has been done yet.

In particular, **the two lanes do not prove that the netlist has only two 16×16 multipliers**: the RTL currently still contains extended multiplication in NORM, coefficient composition, postscale, and interpolation. There is no arbitration/resource sharing across engines yet. The memory arrays are currently RTL synchronous models with host access, not yet bound to the PDK SRAM macro. These two points must be implemented/assessed when moving the functional version to an area-optimized ASIC version; regression results cannot be used to assert that the hardware budget has been met in the architectural documentation.

---

[Read more: hierarchy RTL](<../../source_guide/legacy/README.md>) · [Verification](<../../verification/README.md>) · [Demo model](<../../demos/README.md>) · [Back to documentation table of contents](<../../README.md>)
