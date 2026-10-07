# Architecture research — historical 2026-10-05

> **Category: HISTORICAL SNAPSHOT — 2026-10-05.** This snapshot must not determine current architecture, live status or active tasks.

This is a research reference for the baseline and milestones identified below.
The completed throughput optimization and current evidence are in the
[version 3 implementation review](<../reviews/rtl_change_review_v3.md>) and
[verification status](<../verification/optimization_status.md>).

Reviewed and updated 2026-10-05, Asia/Saigon. Git baseline: commit
[`ca82b2f39ade227ee5e015f9ed02e9d7df6d5f67`](https://github.com/nguyennhutkhanhtom/NPU/commit/ca82b2f39ade227ee5e015f9ed02e9d7df6d5f67).
This document replaces the example Commit A/B/C headings with actual revisions
and includes additional implementation and evidence milestones.

The authority order is RTL and Git diffs, source-matched evidence manifests,
raw reports, then explanatory documents. Historical results apply to their
archived inputs. The latest completed full-top fit is the local **`npu100_a3`** candidate,
which includes the implemented parameter-memory tiling change on top of this
Git baseline. Its evidence and the earlier `fullrtl100_cache2` archive are
**untracked at review time**. Neither is evidence already in the baseline
commit. Older status documents may describe completed runs as pending.

**Decision before P1–P4:** the latest measured candidate reaches **91.15 MHz**, with worst setup
**−0.971 ns** at the unchanged 10 ns clock. The 100 MHz target remains unmet.
The next work must address scalar-result distribution, prompt-token selection,
SIMD rounding control and scalar-return control. Section 18 gives the detailed
implementation and verification plan. The user subsequently approved that
plan: P1–P4 are now implemented as **`npu100_b2`**, all seven regression groups
have passed, and the corrected full-top fit is running. Section 19 records the
implementation and its current-source evidence; no new frequency is claimed
until that fit completes.

## 1. Current architecture

The active full-graph top is [llm_soc.sv](<../../Verilog Source code/llm_soc.sv>).
It implements a fixed NanoFable-compatible autoregressive graph: four layers,
128 channels, four 32-channel attention heads, 384 feed-forward hidden channels,
4,096 vocabulary entries, and a maximum context of 128 positions. This is a
fixed graph, not an arbitrary instruction-programmable model executor.

The host loads parameters, prompt token IDs and configuration, starts execution,
and reads selected token IDs. RTL owns embedding, RMSNorm, Q/K/V projections,
RoPE, KV writes, causal attention, output projection, residual additions,
gate/up/SiLU/multiply/down, final normalization, tied embedding head, sampling,
and subsequent decode iterations. Tokenization and decoded text belong to the
host; intermediate activations and selected-token feedback belong to RTL.

Compute uses signed fixed-point arithmetic, a shared 32-lane SIMD engine,
structural multipliers, an iterative divider and square root, and constant
lookup tables. SRAM interfaces separate storage technology from portable
compute/control. All blocks use one `clk`; the host must meet its synchronous
handshake contract. The reset boundary asserts immediately and releases after
two rising edges.

The current `llm_soc` payload includes independent, continuously clocked
`cache_operand_q` slices. Binary vector operations retain their own `second_q`.
Attention accumulators clear at head entry (`A_QUERY`). These changes coexist
with the earlier continuously clocked SIMD payload pipeline.

The separate `matmulfree` instruction-driven core and `matmul_wrap` remain
reachable legacy designs with their own tests. Their INT8/S16 architecture,
32 KiB parameter SRAM and 8 KiB workspace are not the full language top's
datapath or memory capacity.

**Current evidence:** six source-matched synthetic groups PASS, full graph
**cancelled at the user's requested first-frequency stop**, Quartus
analysis/synthesis PASS, and full-top post-fit timing **FAIL at 91.15 MHz**.
Vendor-free elaboration has not been rerun for the changed memory adapter.
The older seven-group and vendor-free PASS apply to the cache1/cache2 RTL
snapshot, not all current sources. No pretrained application PASS is
established. Quartus is an EDA demonstration backend;
these results are neither board deployment nor ASIC signoff.

Sources: [full graph and formats](<../design/full_rtl_language.md>),
[ASIC portability](<../design/asic_portability.md>),
[SRAM binding](<../design/asic_memory_binding.md>), [rules](<../../AGENTS.md>).

## 2. Module hierarchy

The following tree describes the current elaborated full top. Generated
instances are summarized by count; packages provide constants/types/helpers
and are not hardware instances.

```text
llm_soc
├── u_reset: reset_release                  two ordinary release FFs
├── u_parameters: llm_parameter_ram         8 lanes, each 32 × 24576 bits
│   └── g_ram_lane[0..7].u_storage: pipelined_word_ram
│       ├── g_ip_tiled.g_tile[0..23].u_storage: quartus_word_ram → altsyncram
│       └── g_model.g_tile[*].u_tile: sram_word_tile (alternative branch)
├── u_vectors: llm_bank_ram                 32 lanes, each 24 × 96 bits
│   └── g_bank[0..31].u_storage: pipelined_word_ram → selected SRAM branch
├── u_cache: llm_bank_ram                   32 lanes, each 24 × 4096 bits
│   └── g_bank[0..31].u_storage: pipelined_word_ram → selected SRAM branch
├── u_math: llm_math                        32 SIMD lanes
│   └── g_mul_lane[0..31].g_byte[0..3].u_mul: logic_mul (128 instances)
├── u_scalar_lo/u_scalar_mid/u_scalar_hi: logic_mul
├── u_exp_mul: logic_mul
├── u_noise_mul: logic_mul
├── u_root: isqrt_u64                       declared in norm.sv
├── u_div: div                             NUM_W=64, DEN_W=32
├── u_sig: sigmoid
│   ├── u_bit_mul: logic_mul
│   └── u_lookup: sigmoid_sample            constant table module
├── u_exp_hi/u_exp_lo: llm_exp_sample        constant table modules
└── u_gumbel_lookup: llm_gumbel_sample       constant table module
```

`USE_QUARTUS_MEMORY=1` selects the replaceable technology-leaf branch; only
[quartus_word_ram.sv](<../../Verilog Source code/quartus_word_ram.sv>) explicitly
instantiates vendor memory IP. With the parameter zero, the adapter selects
inferred `sram_word_tile` arrays. This alternative is a behavioral/inferred
storage implementation, not a selected foundry SRAM.

Data flow is parameter/vector/cache response → controller operand registers →
shared arithmetic → rounding/clamping registers → vector or KV write request.
The graph FSM advances on operator completion; the operator waits for memory
valid, arithmetic done and pending-write drain. The host FSM arbitrates
parameter access against graph execution.

Legacy hierarchy, summarized separately:

```text
matmul_wrap → matmulfree
  ├── PC, ins_mem, descriptor_file
  ├── register (regfile.sv), mem_mapping → sram_256_wrapper
  ├── rowwise_dispatch → rowwise_op → sigmoid, logic_mul
  ├── norm_dispatch → norm → isqrt_u64, div, logic_mul
  ├── ternary_mul → acc_mul, logic_mul, postscale_finish
  └── scale_compose → div, logic_mul
```

Sources: [source guide](<../source_guide/legacy/README.md>),
[llm_math](<../../Verilog Source code/llm_math.sv>),
[parameter RAM](<../../Verilog Source code/llm_parameter_ram.sv>),
[bank RAM](<../../Verilog Source code/llm_bank_ram.sv>),
[legacy scheduler](<../../Verilog Source code/matmulfree.sv>).

## 3. Datapath widths

`S` and `U` mean signed and unsigned storage width. `F16` means 16 fractional
bits, not a 16-bit floating-point format. Preserve every rounding and
saturation boundary; matching the final storage width alone is insufficient.

| Current full-top quantity | Width / format | Role |
|---|---|---|
| Host address/write/read | U32 | Byte address and 32-bit transfers |
| Token ID | U12 | Vocabulary 0..4095; prompt/output arrays |
| Parameter row / row address | 256 bits / U15 | 24576 rows, eight host lanes |
| Vector/cache row | 768 bits | 32 × S24/F16 lanes |
| Vector / cache address | U7 / U12 | 96 / 4096 rows |
| SIMD inputs | S24 × S32 | Shared products and reductions |
| SIMD byte partials | S33 | Four 24-by-8 products; high byte signed |
| SIMD pair / product | S41 / S56 | Shift-add reconstruction |
| SIMD reduction | S57 → S58 → S59 → S60 → S61 | Registered 32-lane sum |
| Linear/tied-head accumulator | S39 | Ternary or S8-weight dot accumulation |
| Scalar coefficient/input | U24 coefficient; S39 and S25 operands | Three structural partial multipliers |
| Scalar partial/pair/product | S48 / S56 / S64 | Low/middle/high parts and reconstruction |
| Per-lane raw/rounded result | S64 / S64 | RNE before S24 clamp |
| RMS square sum / root input | U64 | Mean and epsilon addition |
| RMS root / reciprocal | U32 / U25 | Floor sqrt; rounded 2^32/root |
| RoPE cos/sin | S16/F15 | S56 products and S64 sum |
| Attention score | S32 | Saturated score/max storage |
| Softmax weight / weight sum | U25/F24 / U32 | Interpolated exp and normalization |
| Weighted attention accumulator | S56 per lane | Up to 128 causal values |
| Exp delta/interpolation | U25 / U37 | 25-by-12 structural product |
| Divider numerator/denominator | U64 / U32 | U64 quotient, U32 remainder |
| Sigmoid input/output | S16/F12 / U16/F15 | SiLU conversion and multiply |
| Sampling noise/temperature | S24/F16 / U8/F8 | S33 noise product, S64 candidate |
| Graph / operator state | 5-bit enum / 102-bit one-hot enum | Distinct scheduling levels |

The SIMD acceptance edge captures operands. Byte partials, pair sums, products
and five reduction levels follow; `done=valid_q[9]` arrives nine subsequent
rising edges after accepted `start`. Its control pipe is ten bits. Payloads run
continuously; reset clears validity, and consumers wait for `done`.

Important bounds from the numeric contract: 128 S24 squares sum to at most
2^53; epsilon 42950 gives root ≥207 and reciprocal <2^25. Each softmax weight
is ≤2^24, so 128 weights fit U32 and the weighted S24 sum fits S56. The longest
ternary input dimension is 384; the tied-head S8-weight dot fits S39. These
bounds do not authorize moving intermediate clamps or narrowing unrelated
raw operands.

For comparison, [npu_pkg.sv](<../../Verilog Source code/npu_pkg.sv>) defines legacy
activation S8, weight 2 bits, accumulator S18 for K≤512, state/residual S16,
32 ternary lanes and two vector lanes. Those package constants must not be
mistaken for `llm_math`'s S24-by-S32 ports.

## 4. Memory architecture

| Full-top storage | Logical geometry | Capacity | Ownership |
|---|---|---:|---|
| Parameters | 24576 × 256 bits | 768 KiB | Host loads; graph reads |
| KV cache | 4096 × 32 × S24 | 384 KiB | Graph writes K/V and reads causal entries |
| Vector workspace | 96 × 32 × S24 | 9 KiB | Eight buffers of 384 channels |
| Prompt IDs | 128 × U12 | 192 bytes | Host writes; prefill reads |
| Output IDs | 128 × U12 | 192 bytes | Graph writes; host reads |
| Attention scores | 128 × S32 | 512 bytes | Score pass writes; exp pass reads |
| Attention probabilities | 128 × U25 | 400 bytes | Exp pass writes; value pass reads |

KV address is `layer*1024 + position*8 + K/V*4 + head`, represented by
`{layer, position, K_or_V, head}`. A vector buffer occupies 12 rows of 32
channels. Parameter regions include embedding/head data, packed ternary
matrices, scales, gains and RoPE tables; bases are in
[llm_pkg.sv](<../../Verilog Source code/llm_pkg.sv>): `EMB_SCALE_BASE=23040`,
`MATRIX_META_BASE=23552`, `GAIN_BASE=23580`, `ROPE_BASE=23652`.

The three large stores now reach 256 explicit technology leaves: 192 parameter
(8 lanes × 24 tiles), 32 KV and 32 vector. Before the `npu100_a3` change there
were 72 leaves, including eight monolithic parameter leaves. Their logical
total remains 9,510,912 bits. The recent fits
report 9,515,648 block-memory bits, including an additional 4,736 bits for
inferred output and probability arrays. Physical M10K packing uses 1,186 of
1,220 blocks; logical-bit capacity and physical block consumption differ.

For `USE_QUARTUS_MEMORY=1` and more than 4096 rows, the adapter now uses
1024-row tiles with local registered read/write addresses and enables. A
four-tile group shares one registered write payload; registered group responses
feed an explicit balanced response tree. This changes physical distribution
while retaining the existing four-edge deep-adapter read and two-edge write
contract. The short technology branch and inferred branch are unchanged.

Latencies below count the accepting rising edge as edge 1:

| Boundary | Read | Write / completion |
|---|---|---|
| Technology leaf | One edge; disabled read holds output | Commit on edge; same-address read/write returns OLD_DATA |
| `pipelined_word_ram` | 3 edges for ≤4096 rows, otherwise 4 | Commit at edge 2; one request/clock |
| `llm_bank_ram` (current vector/KV) | 5 edges | Lane-masked commit at edge 4; `wr_busy` covers pending writes |
| `llm_parameter_ram` (current depth) | 5 edges for compute; host lane selection adds 1 | Host ACK follows actual leaf commit |

Parameter host access transfers eight U32 lanes per 256-bit row. Parameters
occupy byte addresses below `0x000c0000`; top-level response staging is in
addition to adapter latency. The host keeps address/data stable until ready,
then drops `host_en` for at least one clock. Parameter accesses are excluded
while the graph owns the port. See the exact
[host map](<../../tests/full_rtl/README.md>) and controller source.

Storage and payload registers are unreset. Reset cancels queued enables and
response validity, retaining already committed contents. Cancelling a host
response does not promise rollback of an accepted write. The ASIC leaf must
preserve common-clock 1R1W ports, accepted-request rate, old-data collision
behavior and adapter latency. Mapping small controller arrays to new SRAM
macros would require accounting for any new read edge.

Sources: [memory binding and inferred-array accounting](<../design/asic_memory_binding.md>),
[word adapter](<../../Verilog Source code/pipelined_word_ram.sv>),
[actual-memory tests](<../../tests/full_rtl/tb_memory_ip.sv>).

## 5. Important FSMs

| Controller | Important sequencing | Contract |
|---|---|---|
| Graph (`graph_t`, 24 states) | Embed → attention norm → Q/K/V → RoPE Q/K → cache → attention → O → residual → MLP norm → gate/up/SiLU/multiply/down → residual → next layer; final norm/head/advance/done | Advances on `op_done`; four layers per token; prefill before generation |
| Operator (`op_t`, 102 one-hot states) | `O_P/V/K_REQ` → corresponding WAIT → continuation; math START/WAIT; write/finish; operation-specific arithmetic stages | Waits for accepted valid/done and drains writes before completion |
| Host (`host_t`, five states) | `H_IDLE` capture → `H_EXEC`; optional `H_READ/H_WAIT`; `H_DONE` ACK | Stable request, explicit cancellation, no conflicting parameter ownership |
| Divider | Accepted start → 64 subtract/shift iterations → done | Start while busy ignored; zero divisor has defined flag/result |
| Square root | Accepted start → 32 radix-4 iterations → done | Floor sqrt(U64), U32 result |
| Sigmoid (seven states) | IDLE → READ0 → READ1 → SLOPE → MULTIPLY → ADD → ROUND | Consecutive LUT samples and registered interpolation |
| SIMD validity pipe | Accepted start shifts through `valid_q[0..9]` | Stable captured inputs, one outstanding transaction, done at index 9 |

Attention consists of three causal passes: scores/max, exponent weights/sum,
then weighted values/division. `time_q` ranges only from zero to the current
`position_q`; heads repeat this flow independently. `A_QUERY` clears all
32 attention accumulators before those passes. The graph advances to selected
token feedback only after the head has completed.

The continuation registers `return_p/v/k/m/w/scalar` are one-hot operator
states, not a software stack. They make reuse of physical memory/arithmetic
engines explicit. Datapath updates are visible in generated lane FF blocks;
FSM transitions are visible in the controller, not hidden in tasks/functions.

Sources: [controller RTL](<../../Verilog Source code/llm_soc.sv>),
[divider](<../../Verilog Source code/div.sv>), [sqrt](<../../Verilog Source code/norm.sv>),
[sigmoid](<../../Verilog Source code/sigmoid.sv>).

## 6. Architecture at d9ed792 — autonomous language graph

Commit [`d9ed7921d42731a198f565785a8ae79b20c7c79e`](https://github.com/nguyennhutkhanhtom/NPU/commit/d9ed7921d42731a198f565785a8ae79b20c7c79e),
2026-10-02: **Implement autonomous RTL language graph with verified units and timing evidence**.

This milestone adds the autonomous full-graph execution boundary, replacing
CPU-driven intermediate operator orchestration for this language path. The
legacy core remains separate. It already has the 24 graph states, S24-by-S32
SIMD interface, S56 products and S61 reduction, parameter/vector/KV stores,
causal attention and RTL token selection.

The operator enum has **93** one-hot states at this revision. `llm_math`
has an eight-bit valid pipeline (`done=valid_q[7]`), direct runtime
`a_q[i] * b_q[i]` expressions and procedurally replicated lane stages.
`llm_bank_ram` wraps `banked_word_ram` with two-edge reads, rather than today's
five-edge grouped adapter. No `reset_release` instance appears at this top.
These are historical facts; this revision does not satisfy today's structural
multiply and explicit-register-ownership policy.

Pinned sources:
[controller](https://github.com/nguyennhutkhanhtom/NPU/blob/d9ed7921d42731a198f565785a8ae79b20c7c79e/Verilog%20Source%20code/llm_soc.sv),
[SIMD](https://github.com/nguyennhutkhanhtom/NPU/blob/d9ed7921d42731a198f565785a8ae79b20c7c79e/Verilog%20Source%20code/llm_math.sv),
[bank adapter](https://github.com/nguyennhutkhanhtom/NPU/blob/d9ed7921d42731a198f565785a8ae79b20c7c79e/Verilog%20Source%20code/llm_bank_ram.sv).

## 7. Architecture at a2fa161 — early attention clear

Commit [`a2fa16125030bae0d748f0afbb3f5acc24c35870`](https://github.com/nguyennhutkhanhtom/NPU/commit/a2fa16125030bae0d748f0afbb3f5acc24c35870),
2026-10-04: **Clear attention accumulators at head entry and verify six unit groups**.

By this revision, earlier commits have introduced structural byte multipliers,
explicit generated pipelines, grouped memory adapters and two-FF reset release.
The specific compute change in this commit is small: the per-lane accumulator
clear moves from `A_EXP_STORE && time_q == position_q` to `A_QUERY`.

This removes the current-position comparison from the clear control of
32 × 56 accumulator bits. There are no accumulator reads or additions between
head entry and the old clear point that require the old contents. The weighted
value pass still starts from zero. No graph state, SRAM geometry, arithmetic
format or intended output changes.

The preceding fanout2 fit measured `position_q[2] → attention_acc_q[16][39]`
at −0.345 ns. The later attention1 fit measures a different worst path,
`op[6] → second_q[341]`, and fails at 92.19 MHz. That change of dominant path
does not prove overall timing improvement: placement and backend hold settings
also matter, and the later Fmax is lower.

Evidence milestones after this implementation:
[`b3d3033`](https://github.com/nguyennhutkhanhtom/NPU/commit/b3d3033cf36cd44d6b3dd6ac749c0bbfdd0f1eff)
archives all seven groups and vendor-free elaboration;
[`b9699a7`](https://github.com/nguyennhutkhanhtom/NPU/commit/b9699a7f18a82f01247867dedcabdb045c463d71)
archives its full attention1 timing failure.
Attention regression (`../../tests/full_rtl/evidence/attention1_all_units/results.json`; historical target unavailable in this checkout),
[attention timing](<../verification/timing/fullrtl100_attention1/manifest.json>).

## 8. Architecture at 41eea1a — separate KV payload registers

Commit [`41eea1a6f1ea073937f4bcaf890f0fe22d6d53ac`](https://github.com/nguyennhutkhanhtom/NPU/commit/41eea1a6f1ea073937f4bcaf890f0fe22d6d53ac),
2026-10-04: **Separate cache payload registers; verify synthesis and six unit groups**.

Previously `second_q` captured either an accepted KV response in `O_K_WAIT`
or the first binary vector operand in `B_INPUT0`. This shared a 768-bit payload
register bank, input selection and state-dependent load control.

The commit adds 32 generated, unreset, continuously clocked S24 slices of
`cache_operand_q`, each sampling `k_data`. `A_KEY` and `A_WEIGHT` consume that
bank only after `O_K_WAIT && k_valid`; the RAM holds the response long enough
for the same consumption edge. `second_q` now captures only binary vector
input at `B_INPUT0`. This adds 768 logical payload FF bits without adding
operator states or changing response latency, arithmetic or memory contracts.
The fitted-register difference is not guaranteed to equal 768 because fitting
can duplicate/merge other registers.

This same commit also requests `GLOBAL_SIGNAL "GLOBAL CLOCK"` for
`u_reset|core_rst_n` in the Quartus QSF. Therefore its later cache1 timing
result cannot isolate the effect of the payload split. The forced-routing
candidate fails at 73.97 MHz, with setup and recovery violations.

[`35704b0`](https://github.com/nguyennhutkhanhtom/NPU/commit/35704b084c14925f3a1b52670d1e2147f95b1975)
subsequently archives the all-seven graph PASS and vendor-free elaboration;
[`70c794d`](https://github.com/nguyennhutkhanhtom/NPU/commit/70c794df21e74ec6d928b3043cd114fe86f3e4aa)
preserves the full cache1 timing failure and recommendation to remove forced
global routing. The payload split remains in current RTL.

## 9. What changed between versions

| Dimension | d9ed792 | a2fa161 | 41eea1a | Git baseline ca82b2f |
|---|---|---|---|---|
| Graph ownership | Autonomous RTL graph | Same | Same | Same |
| Operator enum | 93 one-hot states | 102 states | 102 states | 102 states |
| SIMD multiply | Runtime `*` | Structural byte-product trees | Same | Same |
| SIMD response | `valid_q[7]` | `valid_q[9]`, continuous payload | Same | Same |
| Bank read contract | 2 edges | 5 edges | Same | Same |
| Reset release | Direct top reset | Two ordinary FFs | Same | Same |
| Attention accumulator clear | Late exponent pass | Head entry, `A_QUERY` | Same | Same |
| KV/binary payload ownership | Shared `second_q` | Shared `second_q` | Independent cache bank | Same |
| Forced reset global request | Absent | Absent | Added in QSF | Removed in QSF |

The large interval from d9ed792 to a2fa161 contains multiple independent
changes. Do not attribute all differences in this table to the attention-clear
commit itself. Section 15 identifies the intervening revisions.

The ca82b2f change relative to cache1 is backend routing only: RTL and test
inputs remain identical. It preserves the cache split, early clear, two-FF
reset release, 10 ns clock and I/O budgets. The local cache2 fit improves from
73.97 to 90.61 MHz and clears recovery failures, but still fails setup. This
comparison supports rejecting the forced-global candidate; it does not
establish a passing implementation.

The subsequent local `npu100_a3` candidate changes the memory adapter and adds
scoped backend preservation of its address/write-payload copies. `llm_soc`,
arithmetic and lookup assets remain identical to ca82b2f. Section 18 separates
this completed experiment from the next proposed compute/control changes.

## 10. Measured timing problems

Measured paths take priority over width-based hypotheses. The following are
actual post-fit observations, with the source snapshot named explicitly.

| Snapshot | Measured setup path | Slack | Interpretation |
|---|---|---:|---|
| fanout2 | `position_q[2] → attention_acc_q[16][39]` | −0.345 ns | Position-qualified wide accumulator clear; motivated early clear |
| attention1 | `op[6] → second_q[341]` | −0.847 ns | Accepted KV response control into wide shared bank; motivated payload split |
| cache1 | `u_reset\|core_rst_n → u_math\|a_q[13][2]` | −3.519 ns | Forced global routing dominates reset-qualified operand capture |
| cache2, local | Parameter lane 0 `g_ip.read_address_q[2] → ram_block1a37~portb_address_reg2` | −1.036 ns | Large parameter memory address distribution |
| npu100_a3, local | `scalar_round_q[9]~DUPLICATE → g_scalar_output[4].low_data_q[9]` | −0.971 ns | Scalar payload routing across output groups |

The **previous cache2** worst path had zero logic levels, 10.819 ns data delay,
10.192 ns data routing delay (94%) and −0.117 ns clock skew. That failure was
principally a physical SRAM address-distribution problem.
Its recommendations named `g_ip.read_address_q[2]` and `[12]` for duplication.
At slow 0°C its worst setup was −0.559 ns on the same parameter lane's address
bit 12 distribution.

Other **cache2** negative setup paths included `position_q → k_address_q`,
operator controls into attention accumulators, math operand capture,
`chunk_q → op`, and lane-rounded data into math operands. Keep these families
visible in subsequent fits as other paths are repaired. Earlier reset recovery
paths to public `host_rdata` also need continued checking; cache2 and npu100_a3
both pass recovery.

The latest slow-85°C setup report lists 40 paths, all violated. They fall into
four families below. These counts describe the **reported sample**, not every
violating path or endpoint in the full design. Routing percentages refer only
to the data path, not the clock network.

| Current family / representative path | Reported paths | Worst slack | Data delay | Logic levels | Data routing | Source of the problem |
|---|---:|---:|---:|---:|---:|---|
| `scalar_round_q[9] → g_scalar_output[4].low_data_q[9]` | 2 | −0.971 ns | 10.722 ns | 1 | 10.382 ns / 97% | A shared scalar result reaches physically separated result groups; the launch copy has fanout 10 |
| `graph[3] → token_q[9]` | 8 | −0.631 ns | 10.319 ns | 6 | 7.675 ns / 74% | Graph-dependent address/select logic and the prompt-array mux share a cycle; intermediate `position_q~5` has fanout 384 |
| `op[80] → lane_round_q[9][18]` | 27 | −0.265 ns | 9.956 ns | 2 | 8.669 ns / 87% | `NR_ROUND` feeds `WideOr318~0`, a shared control node with fanout 1601 |
| `op[79] → return_scalar[20]` | 3 | −0.047 ns | 9.822 ns | 6 | 7.688 ns / 78% | `L_SAT`, which does not write this register in RTL, remains in its fitted shared control cone |

The other scalar endpoint is group 6. The scalar path runs from an FF at
`X69_Y20` to an FF at `X58_Y60`, taking a substantial routing detour. A single
feeder LUT is not the main delay. Blindly replacing the multiplier or adding
arithmetic stages would not directly repair this path.

At slow 0°C, five of the 40 reported setup paths violate: three token paths
and the same two scalar-group paths. The worst is `graph[3] → token_q[9]`
at **−0.418 ns**. Fixing only the worst slow-85°C endpoint is insufficient.
The recommendations identify scalar, graph and operator nodes for duplication;
they are heuristics, not proof that a backend-only duplication will close timing.

The `op[79]` route includes nodes named `op_debug_prefix[6][102]~10` and
`~42`, followed by `WideNor36~5`, `WideOr474~0` and `WideOr476`. These are
optimized netlist names; they do not establish a source-level dependency on
the public debug output. Isolate the register's actual three write events
before considering any change to the debug encoder.

Possible arithmetic paths to watch after routing improvements are the final
carry-propagate adder in [logic_mul](<../../Verilog Source code/logic_mul.sv>), S64
RNE variable shifts, lane clamp/select control, S56 attention additions, and
iterative divider/sqrt subtractors. These are source-based candidates; they
are not claimed to be the current worst measured paths.

Sources: [fanout2 manifest](<../verification/timing/fullrtl100_fanout2/manifest.json>),
[attention1 manifest](<../verification/timing/fullrtl100_attention1/manifest.json>),
[cache1 manifest](<../verification/timing/fullrtl100_cache1/manifest.json>),
[local cache2 detailed setup](<../verification/timing/fullrtl100_cache2/slow_1100mv_85c_setup.rpt>),
[cache2 recommendations](<../verification/timing/fullrtl100_cache2/slow_1100mv_85c_recommendations.txt>),
[current slow-85°C paths](<../verification/timing/npu100_a3/slow_1100mv_85c_setup.rpt>)
(paths 1, 3, 6 and 29),
[current slow-0°C paths](<../verification/timing/npu100_a3/slow_1100mv_0c_setup.rpt>),
[current recommendations](<../verification/timing/npu100_a3/slow_1100mv_85c_recommendations.txt>).

## 11. Synthesis evidence

### Historical synthesis and functional evidence

[Cache2 synthesis](<../verification/synthesis/cache2/manifest.json>) records
successful analysis/synthesis with zero errors and 12 warnings. Its immutable
capture-time status is `SYNTHESIS_PASS_TIMING_PENDING`; the later local timing
manifest resolves timing independently. The
[map summary](<../verification/synthesis/cache2/llm_soc.map.summary>) reports
47,146 registers, 9,515,648 block-memory bits and zero DSP/PLL/DLL/HSSI use.
Map register count is not fitted register count, and the map summary gives no
ALM utilization.

Cache1 all-seven regression (`../../tests/full_rtl/evidence/cache1_all_units/results.json`; historical target unavailable in this checkout)
matches the 34 RTL assets of the ca82b2f/cache2 baseline after CRLF→LF
normalization. It does not cover the later changed memory adapter. It records
PASS for actual Quartus memory, math, RAM, host protocol, selection edges,
operators and full graph. The synthetic graph uses two prompt tokens, selects
three tokens in RTL, executes 16 layers, checks causality and takes 4,229,462
compute clocks with 196,619 host commands. Compile/runtime warnings are zero.
It is a functional synthetic fixture, not a pretrained-model quality result.

[Vendor-free elaboration](<../verification/portable_elaboration_cache1/results.json>)
records `USE_QUARTUS_MEMORY=0`, 24 module design units, 14 unique module names,
zero errors/warnings and no vendor memory library. This is a `run 0`
elaboration check, not an inference run or ASIC implementation.

### Current candidate evidence

[npu100_a3 synthesis](<../verification/synthesis/npu100_a3/manifest.json>)
records analysis/synthesis PASS, 53,740 mapped registers, zero errors and
12 warnings. Its capture-time `SYNTHESIS_PASS_TIMING_PENDING` status is retained;
the separate completed timing manifest records the failure.

Six-group evidence (`../../tests/full_rtl/evidence/npu100_a2_six/results.json`; historical target unavailable in this checkout)
matches the RTL used for npu100_a3. Actual-memory tests pass 464 checks over
five geometries, including all tile boundaries, sustained read/write collisions
and a partial final tile/group. Math passes 503 transactions, RAM 28 checks,
protocol 29 transactions with 12 cancellations, selection 14 checks, and
operators 17 cases with 3,460 checks, including 128 scalar and 128 clamp cases.
The completed six groups have zero compile/runtime warnings.

Stopped graph evidence (`../../tests/full_rtl/evidence/npu100_a2_stopped/results.json`; historical target unavailable in this checkout)
records cancellation when the first frequency result became available. Its
last progress marker is 500,000 clocks, position 0, generated 0; this is not a
completion result or the exact cancellation clock. No current full-graph PASS
exists. The newly prepared portable-elaboration and additional host-cancellation
scripts were not executed. The older PASS must not be substituted for them.

### Full-top fitted comparisons

All five rows below are `llm_soc` results. Each uses its own archived source
and configuration; the final two rows are local, untracked evidence at review time.

| Timing tag | Worst Fmax | ALMs | Fitted FFs | RAM blocks / bits | Strict gate |
|---|---:|---:|---:|---|---|
| fullrtl100_fanout2 | 96.67 MHz | 51,888 | 48,214 | 1186 / 9515648 | FAIL setup and hold |
| fullrtl100_attention1 | 92.19 MHz | 52,799 | 48,311 | 1186 / 9515648 | FAIL setup and recovery |
| fullrtl100_cache1 | 73.97 MHz | 52,417 | 49,186 | 1186 / 9515648 | FAIL setup and recovery |
| fullrtl100_cache2, local | 90.61 MHz | 52,322 | 49,383 | 1186 / 9515648 | FAIL setup |
| npu100_a3, local/current | 91.15 MHz | 54,651 | 56,075 | 1186 / 9515648 | FAIL setup |

The local cache2 run uses Quartus 25.1std Build 1129, Cyclone V
`5CGXFC9E6F35C7`, seed 1, SPEED optimization and STANDARD FIT. Fitting finishes
2026-10-04 23:10 Asia/Saigon; its manifest is recorded at 23:16. It reports
186 fitted pins and zero DSP/PLL/DLL/HSSI use. Stage diagnostics are map
0 errors/12 warnings, fit 0/4, STA 0/2; STA warning 332148 says timing
requirements are not met. A successful tool exit is not a passing timing gate.

The current candidate retains that tool/device/seed/optimization configuration
and the original SDC bytes. Its fit completes on 2026-10-05 at 01:33 Asia/Saigon;
the timing manifest is recorded at 01:37. Fitted pins remain 186, with zero
DSP/PLL/DLL/HSSI use. Map, fit and STA diagnostics remain respectively
0 errors/12 warnings, 0/4 and 0/2. The fit also reports unavailable subscription
LogicLock support, incomplete/exact I/O placement and ignored fast-I/O wildcard
assignments; do not make the next plan depend on unavailable placement features.

Compared with cache2, Fmax rises only 0.54 MHz while ALMs rise by 2,329 and FFs
by 6,692. RAM capacity and block use are unchanged. Slow-85°C setup improves
by 0.065 ns and TNS improves from −15.220 to −5.989 ns. The parameter-address
family is absent from the current top-40 slow-85°C sample; this does not prove
every parameter path passes or isolate tiling from whole-design placement effects.

### Latest local all-corner timing: npu100_a3

Each cell is **worst slack ns / TNS ns** for `clk`. Every reported
unconstrained-path category has zero setup and hold paths.

| Model | Fmax MHz | Setup | Hold | Recovery | Removal | Pulse |
|---|---:|---|---|---|---|---|
| Slow 1100 mV 85°C | 91.15 | −0.971 / −5.989 | 0.252 / 0 | 0.413 / 0 | 1.642 / 0 | 3.600 / 0 |
| Slow 1100 mV 0°C | 95.99 | −0.418 / −1.784 | 0.238 / 0 | 0.597 / 0 | 3.708 / 0 | 3.548 / 0 |
| Fast 1100 mV 85°C | 144.36 | 3.073 / 0 | 0.132 / 0 | 4.633 / 0 | 2.317 / 0 | 3.798 / 0 |
| Fast 1100 mV 0°C | 167.11 | 4.016 / 0 | 0.115 / 0 | 5.570 / 0 | 0.951 / 0 | 3.787 / 0 |

Thus 18 of 20 corner/check combinations pass, but both slow-corner setup
checks fail. The application gate remains closed. The older legacy
`matmul_free` timing figures cannot be substituted for this full-top result.

Sources: [current manifest](<../verification/timing/npu100_a3/manifest.json>),
[current fit summary](<../verification/timing/npu100_a3/llm_soc.fit.summary>),
[current unconstrained report](<../verification/timing/npu100_a3/extracted_unconstrained.rpt>),
[stop and audit record](<../verification/timing/npu100_a3/decision_summary.json>),
[timing history](<../verification/timing/README.md>).

## 12. Candidate timing optimizations (HISTORICAL proposals)

These are proposals for subsequent measured experiments, not implemented
changes or promised frequency gains. Retain identical constraints and archive
each candidate's source/configuration before evaluation.

| Priority | Candidate | Evidence / reason | Required validation |
|---|---|---|---|
| 1 | Registered scalar result packet and two local distribution clusters | Current worst path, 97% routing; section 18.2 | Exact S64-to-S24 clamp/overflow, destination tags, both scalar consumers, reset at every new stage |
| 2 | Registered prompt address and banked prompt-read pipeline | Both slow corners fail; six levels and fanout 384; section 18.3 | Initial/prefill/decode token order, EOS/context termination, no embedding before token valid |
| 3 | Separate lane register owners and local rounding commands | `NR_ROUND` shared node drives 1601 loads; section 18.4 | Same arithmetic/acceptance edges, per-group commands, reset and RNE/clamp edge cases |
| 4 | Separate `return_scalar` register owner | Unrelated `L_SAT` reaches a three-event register through six levels; section 18.5 | Correct L/A/H return destination and unchanged scalar product pipeline |
| Conditional | Additional KV address, attention divide-round or sampler retiming | Historical KV violations; current slow-0°C divide-round path has only +0.018 ns | Change only after fresh detailed paths justify it; retain all numeric/causal contracts |

Parameter-memory tiling is now implemented and measured. Preserve it while
evaluating these next changes; repeating that proposal as the primary next
action would ignore the current evidence. Scoped backend duplication can
support intentional local copies, but broad duplication, random seed sweeps
or unsupported LogicLock constraints are not substitutes for the measured
register-boundary changes in section 18.

Backend placement, I/O delays, routing requests and device assignments belong
in QSF/backend projects. Use portable standard registers and logic for any
compute/control change; only the technology leaf may use vendor memory IP.
If a proposed memory split changes external latency, it is an architecture
change requiring corresponding FSM and test analysis, not a silent physical
substitution.

Keep the existing early clear and independent KV payload bank unless new
evidence identifies a correctness problem. Do not reinstate the failed broad
forced-global reset request based on an assumed benefit. Full timing, including
reset recovery/removal and I/O hold, must be checked after every fit.

## 13. Functional invariants that must not change

1. **Execution ownership:** RTL performs every graph operation and selected-token
   feedback. Host tokenization/loading/decoding cannot replace compute or sampling.
2. **Graph/model layout:** four layers, four 32-channel heads, current 128/384
   dimensions, packed ternary codes, metadata bases and tied embedding/head layout.
3. **Causality:** attention reads only initialized K/V at times 0..position for
   the current layer/head; head accumulators begin each reduction at zero.
4. **Numeric behavior:** signedness, intermediate widths, exact fixed-point
   scaling, RNE ties, floor sqrt, epsilon, exp interpolation rounding, clamping
   order and saturation limits remain bit-accurate. Reserved ternary code `10`
   remains an error condition; `00/01/11` mean zero/positive/negative.
5. **Sampler behavior:** xorshift state evolution, seed-zero handling, Gumbel
   table, temperature scaling, token exclusions, minimum-length/EOS rules and
   stable tie selection remain consistent with selection tests.
6. **Handshake alignment:** operands capture only on accepted starts; busy
   starts are ignored; results are consumed only with their matching valid/done.
   Continuous payload clocks must not make invalid data architecturally visible.
7. **Cache split:** `A_KEY/A_WEIGHT` consume the accepted cache response;
   `second_q` remains the held binary operand. Preserve that sampling edge.
8. **Memory contracts:** accepted addresses/data/masks stay aligned; old-data
   collisions, write commit, read-valid latency and pending-write drain remain
   consistent for inferred and technology-bound storage.
9. **Reset/cancellation:** immediate assertion, two-edge release, prompt response
   cancellation, public `host_rdata` zero on reset, retained committed SRAM and
   no stale ACK. Cancellation is not a storage rollback guarantee.
10. **Host arbitration:** stable request until ready, at least one idle edge
    between transactions, aligned map access and exclusion of conflicting
    parameter accesses during graph execution.
11. **Completion/error semantics:** token/count/context bounds, error/overflow
    reporting and write drain complete before graph advances or reports done.
12. **RTL policy:** explicit sequential ownership; generate for structural
    replication; only small bounded procedural loops/pure combinational helpers;
    no synthesizable tasks, variable loops, runtime multiply/divide operators
    or vendor datapath/control IP.
13. **Evidence and execution gate:** retain correct changes and immutable failed
    evidence. Pretrained execution requires exact-current all-seven unit/graph
    PASS plus full-top ≥100 MHz at every corner, nonnegative setup/hold/recovery/
    removal/pulse slack, TNS=0 and no unconstrained paths. No masking exceptions
    or weakened expected values. Quartus results do not establish ASIC signoff.

Tests enforcing these contracts:
[math](<../../tests/full_rtl/tb_math.sv>), [RAM](<../../tests/full_rtl/tb_ram.sv>),
[actual technology memory](<../../tests/full_rtl/tb_memory_ip.sv>),
[host protocol](<../../tests/full_rtl/tb_protocol.sv>),
[selection](<../../tests/full_rtl/tb_selection.sv>),
[operators](<../../tests/full_rtl/tb_operators.sv>), [graph](<../../tests/full_rtl/tb_graph.sv>).

## 14. Architecture at ca82b2f — baseline backend routing correction

Commit [`ca82b2f39ade227ee5e015f9ed02e9d7df6d5f67`](https://github.com/nguyennhutkhanhtom/NPU/commit/ca82b2f39ade227ee5e015f9ed02e9d7df6d5f67),
2026-10-04: **Remove failed forced-global routing; verify cache2 synthesis**.

The [QSF](<../../quartus/llm_soc.qsf>) removes only the forced reset global assignment
and replaces its explanatory comments. The 34 RTL assets and seven-group test
inputs remain the cache1 versions. The reset remains two standard FFs, the
public response still clears asynchronously, and host address/data D3 setting 7
and the original SDC remain in the backend.

This commit contains the cache2 synthesis archive. The later local full timing
archive records this exact Git head and matches its canonical configuration,
but was not tracked when this research was written. Its 90.61 MHz result and
remaining parameter SRAM setup failure are historical entries in sections 10–11;
they are not retroactively attributed to the synthesis-only commit.

## 15. Additional real commit milestones

These revisions make the history more useful than three anonymous snapshots.
The titles are the actual Git subjects; implementation milestones and evidence
milestones have distinct roles.

| Commit | Actual subject | Research significance |
|---|---|---|
| [8ddc670](https://github.com/nguyennhutkhanhtom/NPU/commit/8ddc6709d2dbf64311b2ba70bc161c4fd21ae6ff) | Integrate current NPU RTL and publish architecture documentation | Legacy instruction-driven baseline before autonomous graph integration |
| [d9ed792](https://github.com/nguyennhutkhanhtom/NPU/commit/d9ed7921d42731a198f565785a8ae79b20c7c79e) | Implement autonomous RTL language graph with verified units and timing evidence | First full-graph milestone studied in section 6 |
| [d3825b2](https://github.com/nguyennhutkhanhtom/NPU/commit/d3825b25af6c441d201eb2829156be6bb416ca98) | Integrate isolated M10K backend and verify zero DSP/PLL full-top fit | Adds replaceable technology leaf and pipelined word adapter |
| [5e621c4](https://github.com/nguyennhutkhanhtom/NPU/commit/5e621c4a7503e355e98ae1eff1a6960df52a1318) | Pipeline portable arithmetic/control and archive six-unit verification; timing remains 92.75MHz FAIL | Intervening arithmetic/control pipeline work, not timing closure |
| [e75166e](https://github.com/nguyennhutkhanhtom/NPU/commit/e75166e819c1a3f8cf71f85d72a1f2e3e06ef295) | Use portable bit-product logic and verify synthesis/six unit groups | Adds `logic_mul` and structural multiplication across compute blocks |
| [caed560](https://github.com/nguyennhutkhanhtom/NPU/commit/caed5605539f11fe0fd93dab74ead286f4cba8a1) | Make RTL state and pipeline ownership explicit; archive verified gates | Explicit FSM/memory/pipeline ownership and generated lane structure |
| [0fd04be](https://github.com/nguyennhutkhanhtom/NPU/commit/0fd04bebc47aecfc05fdbff81d8645a1528393c6) | Remove SIMD payload enable fanout and condition reset release with standard FFs | Continuously clocked SIMD payload, two-FF reset release |
| [3c8ab8e](https://github.com/nguyennhutkhanhtom/NPU/commit/3c8ab8e4f3693b4b3e47a2cb30f4ccaea51de372) | Bound measured SRAM address fanout and archive synthesis-pass physical candidate | Memory address locality/fanout work preceding attention changes |
| [a2fa161](https://github.com/nguyennhutkhanhtom/NPU/commit/a2fa16125030bae0d748f0afbb3f5acc24c35870) | Clear attention accumulators at head entry and verify six unit groups | Implementation studied in section 7 |
| [41eea1a](https://github.com/nguyennhutkhanhtom/NPU/commit/41eea1a6f1ea073937f4bcaf890f0fe22d6d53ac) | Separate cache payload registers; verify synthesis and six unit groups | Implementation studied in section 8; also adds backend global request |
| [35704b0](https://github.com/nguyennhutkhanhtom/NPU/commit/35704b084c14925f3a1b52670d1e2147f95b1975) | Verify cache1 full graph and vendor-free elaboration | Seven-group and portable elaboration evidence for the cache1/cache2 RTL snapshot |
| [70c794d](https://github.com/nguyennhutkhanhtom/NPU/commit/70c794df21e74ec6d928b3043cd114fe86f3e4aa) | Preserve cache1 timing failure and global-routing recommendation | Preserves failure instead of treating successful fitting as closure |
| [ca82b2f](https://github.com/nguyennhutkhanhtom/NPU/commit/ca82b2f39ade227ee5e015f9ed02e9d7df6d5f67) | Remove failed forced-global routing; verify cache2 synthesis | Git baseline before local parameter tiling; section 14 |

## 16. Evidence provenance and reproduction

The current `llm_soc.sv` canonical-LF SHA-256 is
`5abac9ed9dde98138c4e5928fe7638e302ca4bf9a49b38eeafd373826a10fb9e`.
That compute/controller file is unchanged by the local tiling experiment.
The current memory adapter's canonical-LF SHA-256 is
`691f21844bfe3deae271a26e503b6d667948a70fd742d8b2d9a067039b49162a`.
It differs from cache1/cache2. The npu100_a3 stop/audit record reports a
successful audit of all 34 current RTL assets, 63 archived reports and 37
source/configuration ZIP members; its configuration and command provenance
are in the timing manifest. The original SDC bytes are unchanged. This is
the recorded audit from the implementation run, not a newly executed signoff.

The [source archive record](<../verification/timing/npu100_a3/source_archive.json>)
identifies the immutable ZIP with SHA-256
`e403ab53fa4647ba3a41883be00e1af5375892d428170a9c8800d880d8f93683`.
Use this snapshot with the six-group and cancelled-graph records for the
current candidate. Matching source evidence remains applicable across
documentation-only edits; matching a Git subject alone is insufficient.

Useful read-only Git comparisons, without checking out or reverting history:

```powershell
git show d9ed792:'Verilog Source code/llm_soc.sv'
git show d9ed792:'Verilog Source code/llm_math.sv'
git diff d9ed792 a2fa161 -- 'Verilog Source code' quartus/llm_soc.qsf
git show a2fa161 -- 'Verilog Source code/llm_soc.sv'
git show 41eea1a -- 'Verilog Source code/llm_soc.sv' quartus/llm_soc.qsf
git diff 70c794d ca82b2f -- 'Verilog Source code' quartus/llm_soc.qsf
```

Fresh validation uses [run_units.ps1](<../../tests/full_rtl/run_units.ps1>) and
[timing runner](<../../tools/timing/run.ps1>), with unique work-library/evidence tags
and archived input hashes. Preserve completed archives. No simulation,
synthesis or pretrained execution was rerun to author this documentation.

## 17. Remaining research questions

The local-memory experiment did not close timing: it reached 91.15 MHz and
changed the dominant path. The next measured question is whether the four
targeted changes in section 18 clear both slow-corner setup failures while
retaining passing hold/recovery/removal/pulse checks. A full-top fit is needed;
isolated arithmetic Fmax or synthesis success cannot answer it. The top-40
reports can hide additional path families that emerge after the first fixes.

The ASIC questions remain open: foundry SRAM selection and views, leaf mapping,
standard-cell synthesis/STA at real library corners, DFT, physical design and
signoff. The historical vendor-free elaboration demonstrates a useful
portability boundary; it must be repeated on current sources and is not
completed ASIC implementation.

Pretrained text generation and decoded quality assessment remain dependent on
the strict functional/timing gate. Synthetic graph PASS demonstrates execution
and numerical/protocol checks; it cannot substitute for a permitted trained
application run.

## 18. SUPERSEDED: Detailed plan to reach 100 MHz from npu100_a3

### 18.1 Scope, target and experiment order

**Status: proposed, not implemented.** The user allows internal latency changes
while requiring numerical results and external protocol behavior to remain
correct. The starting point is the current tiled adapter plus unchanged
ca82b2f compute/control, not a checkout of an older revision. Preserve the
correct cache split, early accumulator clear, reset release, structural
arithmetic, LUT contents and all historical evidence.

The recommended next candidate contains **P1 through P4 below**. All four
families already have negative slack, so repairing only the scalar worst path
does not provide a credible full-top closure candidate. Implement and validate
the changes in that order, recording each delta, then run one source-matched
full-top fit. The user's previous instruction to stop at the first frequency
result must not turn into an unbounded sequence of tuning runs: report the
completed result and stop; any further iteration needs subsequent direction.
This document itself starts no implementation or EDA run.

| Work item | Minimum improvement to reach zero on its current worst path | Engineering target | Principal files |
|---|---:|---|---|
| P1: scalar distribution | 0.971 ns | Registered hops with limited fanout; target at least +0.20 ns setup margin | `llm_soc.sv`, scalar-clamp/operator fixtures |
| P2: token fetch | 0.631 ns at 85°C; 0.418 ns at 0°C | Separate graph decision, local prompt read and token commit | `llm_soc.sv`, graph/protocol/operator fixtures |
| P3: rounding control | 0.265 ns | Remove the 1601-load shared rounding node; preserve current rounding edges | `llm_soc.sv`, QSF for local-copy preservation, operator fixtures |
| P4: scalar return owner | 0.047 ns | A register controlled by its three actual writer states | `llm_soc.sv`, scalar/operator/selection fixtures |

These are measured deficits and design targets, **not predicted timing gains**.
The +0.20 ns margin is a preferred robustness target under the original 10 ns
constraint, not an altered clock constraint or a replacement for the required
nonnegative-slack gate. New placement, clock skew and previously hidden paths
can change the limiting family.

### 18.2 P1 — pipeline scalar completion and local distribution

**Source:** `llm_soc.sv`, declarations around lines 263–279,
`g_scalar_output` at lines 653–669, linear completion at lines 803–809 and
attention completion at lines 936–943. These line numbers refer to npu100_a3.

Currently `L_FLAGS` or `A_FLAGS` sends the shared S64 `scalar_round_q` to eight
group-local low-data/clip registers. `L_SAT/A_SAT` then produces the selected
S24 `scalar_group_q`, which four nearby SIMD lanes can consume. The selected
group has a distinct enable, but a data bit can still travel a long route from
the shared source. Merely duplicating the whole S64 register eight times adds
load and does not define a timing boundary.

Use a **26-bit completion packet**: low 24 bits plus signed high/low clamp
flags. Compute flags from the full S64 value using the existing bounds
`+8388607` and `−8388608`, before discarding any upper bits. Register the packet
once with its 3-bit destination group and linear/attention kind. Route it
through two registered clusters: groups 0–3 and groups 4–7. Each cluster
accepts only its tagged result and feeds four local S24 result registers.
Retain the existing group-to-four-lanes output structure.

| Edge / state before edge | Current behavior | Proposed behavior |
|---|---|---|
| E0: `L_ROUND` or successful `A_DIV_WAIT` | Produce S64 rounded result | Unchanged |
| E1: `L_FLAGS` / `A_FLAGS` | Capture low bits/flags in selected output group | Capture central packet, group tag and kind |
| E2: new `SC_ROUTE` | Currently the SAT edge | Capture packet and local group tag in selected cluster |
| E3: `L_SAT` / `A_SAT` | Currently STORE/PACK | Select min/max/low bits into selected `scalar_group_q`; apply existing linear overflow behavior |
| E4: `L_STORE` / `A_PACK` | Subsequent continuation | Existing write-vector capture and continuation |

This adds **one clock per linear output row or attention output lane**. Append
`SC_ROUTE` at a new operator index rather than renumbering existing indices;
increase `OP_COUNT` consistently. The 7-bit debug index still has capacity.
The captured kind selects the existing L or A SAT continuation after routing.
Keep the states, payload registers, tags and valid control explicitly visible
in ordinary RTL, with one sequential owner per register.

Implementation details and correctness obligations:

1. The destination is `matrix_row_q[4:2]` for linear output and `lane_q[4:2]`
   for attention. Capture it with the packet; do not reconstruct it from an
   advanced row/lane counter. Freeze the original counter until STORE/PACK
   exactly as in the current schedule.
2. The central packet drives two cluster payload banks instead of eight
   separated group banks. Each cluster has its own qualified write event.
   Remove superseded group-local low-data/clip storage only after replacing
   every consumer, including the selected-group overflow test in `L_SAT`.
3. Keep `scalar_round_q` and its other uses unchanged. Attention score scaling,
   score-memory updates, head logits, sampling and signed division completion
   must not consume this S24 packet in place of their existing wide value.
4. Linear saturation must set the existing sticky `overflow_out`; attention
   saturation must retain its current behavior without setting that flag.
   Do not clear an earlier overflow when a later packet is in range.
5. Reset cancels packet/cluster validity and pending consumption. Payload FFs
   can remain unreset. A stale cluster value must never cause a store or an
   overflow after reset, an aborted operation or a fresh launch.
6. Check the mapped copies and routed hops. If synthesis merges intended
   locality, use narrowly scoped backend preservation after inspecting actual
   node names. Do not add device attributes to portable compute RTL.

Directed verification must cover both consumers, all eight groups and all
four lane positions within a group; exact limits and one count beyond each;
S64 extremes; large upper bits with misleading low-24-bit patterns; alternating
positive/negative/in-range packets; sticky overflow; and reset at E1/E2/E3.
Assert that only the tagged group/lane changes and the expected write mask,
address and payload reach the memory interface once.

The existing `check_scalar_clamp` fixture currently waits two clocks after
depositing FLAGS. Change its explicit expectation to the documented three
clocks through ROUTE and SAT; retain the independent S128 clamp and overflow
comparisons. This is an authorized latency update, not removal of a check.

### 18.3 P2 — register prompt addressing and token commit

**Source:** the graph owner at `llm_soc.sv` lines 485–543, host prompt writes
around lines 374–376 and embedding dispatch around line 700. The fitted
`graph[3]` name is a mapped state node; do not infer a source state solely
from the bit number.

The current token register shares the graph block and selects three sources:
`prompt_memory[0]` at launch, `prompt_memory[position_q + 1]` for prefill and
`best_token_q` for generated-token feedback. A graph decision, address/control
selection and large combinational prompt read all reach the token register in
one cycle. Separate these boundaries while retaining the 24 existing graph
state IDs and their architectural phase transitions.

Add a small explicit token-fetch pipeline alongside the graph FSM. Keep graph
entry into `G_EMBED` at the same decision edge, but gate its operator dispatch
until `token_valid_q` is set. Use registered request metadata and a held selected
token for decode feedback. No new graph enum values are needed; public graph
debug IDs and graph-visit assertions can remain unchanged.

| Edge | Token-fetch work | Graph/operator behavior |
|---|---|---|
| T0: accepted token-change event | Register prompt address, prompt/feedback selector and feedback payload where applicable; clear prior token-valid | Enter existing `G_EMBED`; do not issue an embedding memory request yet |
| T1 | Read eight local 16-token prompt groups into eight U12 bank-response registers | Keep embedding dispatch waiting |
| T2 | Select the tagged bank response or held feedback token into `token_q`; assert token-valid | Continue to hold embedding dispatch on this edge |
| T3 | Consume token-valid when starting embedding | Existing embedding parameter request uses the committed token |

This adds **two clocks per embedding entry** relative to the current T1
dispatch. The prompt storage remains the same 128 × U12 host-written array.
Express the eight 16-entry read groups with structural `generate for`; a
constant bank and registered four-bit local address select each bank word.
Register the high three address bits with the read validity, then use an
eight-way bank select at T2. Thus graph decode and the full 128-word selection
do not share a cycle. This is ordinary register/mux RTL, without vendor RAM IP
in the controller. The additional bank-response payload is 96 FF bits plus
small metadata; actual fitted area must be reported, not inferred from that
logical count.

There are exactly three request events, with the original priority and guards:

| Event | Request contents and preserved behavior |
|---|---|
| Valid idle launch | Address 0; layer/position/generated reset as today; invalid prompt/max/context combinations still report error and do not start embedding |
| End of layer 3 while another prompt token remains | Address is the **old** `position_q + 1`; increment position and reset layer once; other `G_NEXT` cases do not request a token |
| Continuing `G_ADVANCE` | Hold `best_token_q`; increment position/reset layer once; preserve the output-memory write and generated-count increment at the original edge |

The terminal `G_ADVANCE` cases—maximum generated count, EOS token 1, or
position 127—must not request another embedding. Preserve the graph block's
`op_fault_q` and `op_done` priorities when deriving request events; a simple
unqualified `graph == G_NEXT` expression is not equivalent. `token_q` and all
fetch-valid registers must each have one owner. Reset/fault cancels pending
validity, and a new accepted launch cannot consume an earlier response.

Host writes to prompts/configuration are already excluded by `core_running`;
retain that arbitration and all host ACK behavior. Keep the original ready,
running, output-read restrictions and completed-token semantics. Internal
stall clocks must not advance PRNG state, layer/position counters or outputs.

Verification must exercise prompt indices 0, 15/16, 31/32 and 126/127;
single-token and multi-token prefill; last-layer transitions; feedback with a
different best token each time; EOS/length/context termination; invalid starts;
and reset during each fetch phase followed by a new prompt. Assert no embedding
parameter request before token-valid, and exactly one request sequence per
eligible embedding entry. Keep all existing graph visit counts, token outputs,
causal checks and host responses.

The standalone embedding fixture forces `G_EMBED` and preloads `token_q`,
bypassing the real graph launch. Update that fixture to establish the new
token-valid precondition explicitly, and separately test the real host-driven
fetch path. Do not infer integration correctness from a forced-register test.

### 18.4 P3 — isolate lane owners and prepare local round commands

**Source:** `g_simd` at `llm_soc.sv` lines 550–635 and normalization states
around lines 845–850. The measured endpoint is a rounded-data register, but
the failing launch signal is control, not the RNE adder. The fitted
`WideOr318~0` fanout of 1601 is the immediate target.

Split the broad per-lane case into explicit owners for `math_a_q`, `math_b_q`,
`ternary_code_q`, `lane_raw_q`, `lane_round_q`, `rotation_cos_q`,
`attention_acc_q`, `sigmoid_inputs_q` and `sigmoid_values_q`. Each block lists
only the states that write its register. Preserve all RHS expressions,
qualifiers, hold behavior and edge ordering; retain the existing independent
cache operand and write-vector owners. Remove original assignments when moving
them so no register gains a second driver.

Owner separation alone does not guarantee control locality. For the measured
shift-by-16 branch, introduce **eight registered round commands**, one per
four-lane group, prepared on the existing predecessor edge:

| Edge | Operator state before edge | Payload action | Local control action |
|---|---|---|---|
| R0 | `N_RECIP` or `B_CALC` | Existing `lane_raw_q <= extend56(math_product)` | Each group's round16 command captures true |
| R1 | `NR_ROUND` or `B_ROUND` | Round the R0 raw value by 16 into `lane_round_q`, using its group's command | Command returns low unless another legitimate predecessor occurs |
| R2 | `NR_CLAMP` or `B_CLAMP` | Existing clamp/operand or write-vector capture | No stale round request may remain |

Both predecessor transitions are unconditional in current RTL. This prepares
the enable one edge early without sampling data early and adds **zero clocks**.
The round command must match the current NR/B round phase on every reachable
sequence; reset clears all commands. Data and commands must not be delayed
independently or gated by unaccepted math starts. Add a directed assertion of
this phase relationship, including reset and restart.

Use the group-local command only for the shift-16 branch of the dedicated
round owner. Keep the other exact source/shift mappings:

| Writer | Source / operation |
|---|---|
| `E_ROUND` | S64 raw, RNE shift 8 |
| `NR_ROUND`, `B_ROUND` | S64 raw, RNE shift 16 |
| `N_ROUND` | S64 raw, RNE shift 12 |
| `R_ROUND`, `S_ROUND` | S64 raw, RNE shift 15 |
| `S_INPUT` | Sign-extended S24 vector input, RNE shift 4 |

Identical local command FFs can otherwise be merged. Preserve these eight
intentional copies with exact, scoped `DONT_MERGE_REGISTER` assignments in the
Quartus backend; verify the fitted netlist retains them and each drives its
own four-lane group. Keep device settings out of portable RTL. Do not clone
the complete 102/103-bit FSM per lane or introduce vendor control IP.

Check whether the 1601-load shared node disappears and whether a predecessor
control, raw-data enable or another rounding mode becomes limiting. If it
does, use its new detailed path to choose the next change. Do not assume
source-code separation or a preservation assignment proves physical locality.

Verification retains full S128 references and covers all lane groups; positive
and negative ties with even/odd retained LSB; values around zero and clamp
bounds; normalization reciprocal-clamp-gain ordering; residual/GMUL/SiLU/RoPE
operations; accepted-start/done alignment; and cancellation between R0/R1/R2.
The early `A_QUERY` accumulator clear and accepted cache-response sampling
edges must remain exactly as before.

### 18.5 P4 — give scalar-return state its own register owner

**Source:** `return_scalar` declaration at line 229, its writes at lines 787,
887 and 1008, and its consumption at `SC_SUM`, line 801. `L_SAT` at index 79
does not write this register, yet the fitted path from it is six levels deep.

Move the three writes from the main operator case into a dedicated sequential
block, under the same `core_rst_n` qualification:

| Actual writer | Held return value |
|---|---|
| `L_COEFF` | `L_ROUND` |
| `A_SCALE` | `A_SCORE` |
| `H_COEFF` | `H_ROUND` |

Preserve the one-hot return representation and hold in every other state;
do not change the scalar multiply/pair/sum pipeline or its consumption edge.
The payload is currently unreset and assigned before use; preserve that
contract rather than adding an unnecessary wide reset load. This adds no
states or latency and leaves the scalar fixture's deliberate `O_IDLE` return
injection usable.

Require the mapped return-register cone to depend on these writer events,
without the unrelated L_SAT-wide priority/hold qualification. Verify each
return path through the existing scalar and operator tests plus the head
selection tests. A debug encoder rewrite or binary return re-encoding is not
part of this candidate; consider it only if a new measured path justifies it.

### 18.6 Latency, throughput and implementation boundaries

P1 adds one edge per scalar completion. P2 adds two edges per embedding entry.
P3 and P4 preserve operation latency. Parameter/vector/KV adapter latency,
memory throughput, host transaction protocol, SIMD accepted-start latency,
divider/sqrt completion and arithmetic definitions remain unchanged.

For the existing two-prompt/three-output synthetic fixture, there are 16 layer
executions. Each layer produces 1,408 linear rows (five 128-row and two
384-row projections) plus 128 attention output lanes. P1 therefore adds
`16 × (1408 + 128) = 24576` clocks. Four embedding entries add eight clocks
under P2. The planned increase is **24,584 compute clocks** if no other stalls
change. Using the historical 4,229,462-clock reference gives an expected
4,254,046 clocks; this is a scheduling estimate, **not a new measured PASS**.
The current 5,000,000-clock graph bound should remain sufficient. Do not
increase watchdog limits to hide a deadlock or unexplained extra iterations.

The first candidate should change portable control/datapath only in
`llm_soc.sv`, the narrowly scoped backend command-copy assignments, and tests
required for the explicit new schedule and boundary coverage. Keep packages,
LUTs, arithmetic helpers, structural multipliers/divider, SRAM leaf and tiled
adapter unchanged. Do not move clamps, narrow accumulators, approximate RNE,
change ternary decoding or change sampling policy to obtain frequency.

The small added packet/token/control banks may replace existing low-data/flag
banks; logical FF counts do not predict final ALMs or registers. Report the
fresh fitted totals against 54,651 ALMs and 56,075 FFs. The already high
1186/1220 RAM-block use is a reason to avoid speculative new SRAM replication.
Physical constraints and any technology replacement remain backend concerns.

### 18.7 Verification and evidence sequence for a later implementation

1. **Freeze inputs before editing.** Keep npu100_a3 and all failed/cancelled
   archives immutable. Record current RTL/test/backend hashes, source archive,
   Git status and planned files. Use new evidence and work-library tags; do not
   reuse the existing `npu100_a*` directories or reset the workspace.
2. **Implement P1–P4 with local validation between changes.** Inspect register
   ownership and transition tables; compile the whole design and run the
   affected numerical/protocol fixtures after each meaningful delta. Assertions
   must cover tags, validity, reset and the documented additional edges. Keep
   all old numerical, mask, causal and handshake expectations.
3. **Run the complete exact-current synthetic regression before the fit.** Use
   [run_units.ps1](<../../tests/full_rtl/run_units.ps1>), an unused `WorkLibraryName` and
   `EvidenceTag`, and the installed verified memory-model binding. Do not use
   `-UnitsOnly` for the final record. All seven groups, including the full graph,
   must complete PASS on the frozen candidate; a partial or cancelled graph
   cannot inherit the older PASS. Record the actual compute-clock count.
4. **Verify technology binding and cancellation.** Run the actual vendor-leaf
   memory tests, current-source vendor-free full-top elaboration, and the
   additional host-cancellation probe. The prepared
   [portable runner](<../../tests/full_rtl/run_portable_100mhz.ps1>) and
   [cancellation runner](<../../tests/full_rtl/run_host_cancel_100mhz.ps1>) are currently
   unexecuted helpers; inspect and validate them as part of that run. Confirm
   that only the SRAM technology leaf instantiates vendor IP and that the
   portable elaboration has no vendor-memory design units.
5. **Freeze the verified candidate and run one full-top fit.** Explicitly pass
   `-Project 'quartus/llm_soc'` to [run.ps1](<../../tools/timing/run.ps1>), whose default
   is the legacy top. Use the same Cyclone V device, seed 1, SPEED/STANDARD FIT,
   10.000 ns clock, clock uncertainty and existing I/O budgets. Do not introduce
   false paths, multicycle exceptions or reset/host path exclusions. Append a
   unique tag such as `npu100_b1` only if unused at execution time.
6. **Collect and audit the completed result.** Archive map/fit/STA logs, source
   and configuration, all four PVT models, Fmax/restricted Fmax, setup, hold,
   recovery, removal, pulse and unconstrained reports. Capture detailed paths
   for the four old families and the new global worst paths, plus fitted copy
   counts/fanout and resources. Request a larger bounded path sample, e.g. 200
   per model, in the new evidence set so the old top-40 cutoff is not mistaken
   for complete path coverage. Check hashes before/after the run and the strict
   gate result. Never edit the older reports to append new extraction results.
7. **Stop at the frequency result.** Report measured Fmax at every corner,
   worst slack/TNS, all check categories, resource deltas, functional status
   and exact report links. Do not launch a second fit or pretrained application
   automatically. If timing fails, identify the new limiting cone and retain
   the failure as the evidence for a subsequent decision.

Running functional verification before the fit makes the requested frequency
stop compatible with a completed graph result, unlike the prior interrupted
parallel run. Any RTL, numeric-asset or constraint edit after verification
invalidates the corresponding exact-current evidence and requires the affected
checks again. Documentation-only edits do not change RTL equivalence.

### 18.8 Closure criteria and contingencies

**100 MHz closure requires all conditions below together:**

- Full-top `llm_soc` post-fit Fmax and restricted Fmax are at least 100 MHz
  at slow 85°C, slow 0°C, fast 85°C and fast 0°C, all at 1100 mV.
- Setup, hold, recovery, removal and minimum-pulse slack are nonnegative;
  TNS is zero for every corner/check; every unconstrained-path category is zero.
- The same RTL/numeric sources have all-seven synthetic PASS, correct actual
  memory behavior and the required reset/host checks; no stale artifact is
  substituted for a new-source result.
- The mapped design uses no runtime multiply/divide or vendor arithmetic/control
  IP, retains the portable SRAM boundary, and fits the demonstration device.
  Report backend warnings and actual resource use alongside timing.

If another path limits the first candidate, the next decision follows that
evidence. Known watch points are the attention division rounding path
(`div_denominator_q[21] → scalar_round_q[62]`, +0.018 ns at slow 0°C), sampler
noise logic (`random_q[30] → noise_product_q[32]`, +0.122 ns there), host outputs,
KV address generation and reset recovery/removal. These near-critical or
historical paths are **not yet justification for speculative arithmetic changes**.
For a later measured division-completion failure, a separate rounding-decision,
quotient-increment and signed-result sequence would need its own exact
remainder/tie/sign analysis and done/valid schedule. Do not move those operations
or relax their test references in the current candidate.

A successful full fit or a passing arithmetic submodule alone is insufficient.
Even a passing Quartus result demonstrates closure only for this backend and
constraint set; foundry-cell and SRAM timing, DFT, physical design and ASIC
signoff remain separate work. Pretrained execution remains prohibited until
the complete exact-current functional and timing gate passes, and is outside
this requested analysis-and-plan task.

## 19. Approved P1–P4 implementation: npu100_b2

The user approved execution of Section 18 and retained the instruction to stop
at the first frequency result. P1–P4 are implemented only in the portable top
`Verilog Source code/llm_soc.sv`. The pre-existing parameter-memory tiling and
all numeric assets are preserved. The new top's SHA-256 is
`12fc257f81ea059bbde9ff018f9a56b3c5b633f240862ad25e7668b17c767f77`.

| Change | Implemented behavior | Added latency |
|---|---|---|
| P1 | Full-S64 clamp decisions and S24 completion packet → two tagged registered clusters → selected S24 group → masked workspace lane | One clock per linear row/attention output lane |
| P2 | Capture prompt address/feedback → eight local prompt-bank reads → token commit/valid → embedding dispatch | Two clocks per embedding dispatch |
| P3 | Explicit independent lane payload owners; eight local round16 commands captured on N_RECIP/B_CALC | None |
| P4 | Independent held scalar-return owner, written only by L_COEFF/A_SCALE/H_COEFF | None |

Backend preservation of the eight command registers is scoped to exact names
in `quartus/llm_soc.qsf`. The SDC byte hash remains identical to the starting
candidate: `1be537c7a2fcd99ab244cfedcb7722c208d839b9b02ea11c557152e467ddf277`.
No clock, I/O budget, false path or multicycle exception was added or relaxed.
The reporting helpers collect 200 global paths per corner, a separate bounded
20-path sample per changed family, and fitted register copies/fanout/locations.

### 19.1 Completed functional verification

The exact-current all-seven regression completed **PASS** with the installed
actual vendor SRAM models. Compile and runtime diagnostics are clean. Frozen
logs, binding reports, sources and test inputs are in
all-seven evidence (`../../tests/full_rtl/evidence/npu100_b1_all/results.json`; historical target unavailable in this checkout).

| Group | Completed result |
|---|---|
| Actual memory | 464 checks; five geometries; OLD_DATA; all tile boundaries and partial tile/group coverage |
| Math | 503 transactions; nine reset phases; 513 table and 1536 bit checks; S128 reference |
| RAM | 28 checks; masks, latency, sustained/back-to-back operations and reset phases |
| Protocol | 175 transactions; 12 original cancellations; 15 added token-pipeline cases |
| Selection | 14 checks, including minimum-score and stable ties |
| Operators | 17 operators; 4944 checks; 128 scalar products; 516 clamp cases; six scalar resets; two directed round cases and six rounding resets; S128 reference |
| Full graph | Two prompt tokens, three expected output tokens, 16 layer executions, causal reads, status/phase checks; **4,254,046 compute clocks** and 196,619 host commands |

The measured graph increase is exactly 4,254,046 − 4,229,462 = **24,584 clocks**,
matching 24,576 scalar-distribution clocks plus eight token-fetch clocks. The
original 5,000,000-clock watchdog and all numerical/token/causal expectations
were retained. The graph simulation completed in 1:34:16 wall time; simulation
wall time and a 10 ns testbench clock are not post-fit frequency measurements.

[Portable elaboration](<../verification/portable_elaboration_npu100_b1/results.json>)
also passed: `USE_QUARTUS_MEMORY=0`, 24 module design units, zero errors/warnings,
and no vendor-memory library loaded. This is full-top elaboration, not a second
numerical graph run or ASIC signoff.
Host cancellation (`../../tests/full_rtl/evidence/npu100_b1_host_cancel/results.json`; historical target unavailable in this checkout)
passed seven phases/14 checks on the actual vendor leaf: one pre-execute
cancellation, six accepted-write commits, and seven own-commit-before-ACK cases
with one idle edge. Compile/runtime diagnostics are clean.

Task-specific RTL change accounting is **(186 added + 93 deleted) / 5072
baseline RTL code lines × 100 = 5.5008%**. Only `llm_soc.sv` enters the numerator;
tests, documentation, reporting helpers, blank/comment-only lines, MEM assets
and the pre-existing adapter edits are excluded. See
[raw accounting](<../verification/npu100_b1_baseline/change_accounting.json>) and
[implementation review](<reviews/rtl_change_review_v2.md>). Intermediate fixture failures
and corrected results remain archived; numerical expectations were not relaxed.

### 19.2 First full-top post-fit measurement

**RUNNING; no frequency result yet.** The active evidence tag is
`docs/verification/timing/npu100_b2`. The 34 RTL/numeric assets and three
configuration files were archived before map/fit; all 37 archive members match
the recorded inputs. Quartus 25.1std uses the same Cyclone V device, seed 1,
SPEED/STANDARD FIT and 10.000 ns constraints. The completed result will record
all four corners, all five slack/TNS categories, unconstrained paths, resource
deltas, fitted copy/fanout observations and the strict gate result. No second
fit or pretrained application is authorized by this frequency-stop sequence.

The initial `npu100_b1` attempt completed synthesis but was stopped before
frequency measurement. Quartus read the braces around exact preservation
targets as literal node-name characters, emitted 16 critical warning 136021
messages and merged `round16_group_q[1..7]` into `[0]`. The source/configuration
archive, completed map reports and partial fit log remain immutable in
[cancelled B1 evidence](<../verification/timing/npu100_b1/cancellation.json>).
The correction uses the project's normal quoted QSF node-name syntax. It
changes neither portable RTL nor SDC; B2 uses the same all-seven PASS inputs.
The mapped and fitted register copies must be inspected before claiming local
distribution was retained.
