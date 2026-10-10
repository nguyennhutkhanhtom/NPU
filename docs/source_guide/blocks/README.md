# Guide source by module

<!-- reading-navigation:start -->
[Documentation](../../README.md) → [02 · Architecture](../../02-architecture/README.md) → Module catalog

| Reading guide | Document |
|---|---|
| New to the subject | [NPU and RTL fundamentals](../../00-start-here/fundamentals.md) · [Glossary](../../00-start-here/glossary.md) |
| Learn the RTL syntax | [How to read the SystemVerilog](../../00-start-here/reading-systemverilog.md) |
| Read first | [Full RTL graph](../full_graph.md) |
<!-- reading-navigation:end -->

> **Category: GUIDE.** Read [full graph](../full_graph.md) first; [hierarchy legacy](../legacy/README.md) describes `matmulfree`.

For every module page, “responsibility” names the behavior the block owns;
“contract” names behavior its callers may rely on; and a cycle/edge count starts
from the documented acceptance event. A diagram is an architectural aid, not a
replacement for exact RTL. New readers should review [RTL fundamentals](../../00-start-here/fundamentals.md)
and the [glossary](../../00-start-here/glossary.md) before interpreting widths or
pipeline labels.

The source links point to the current implementation. The annotation describes the responsibility
tasks and contracts without copying RTL. The diagram follows the [shared visual style](../../diagrams/diagram_style.md).

## What each `always_comb` block is doing

`always_comb` describes combinational equations: muxes, decoders, comparisons,
next-value arithmetic, or table lookup. It does not itself add a register or wait
for a clock edge. Most blocks assign safe defaults first and then override them
for a state/opcode; this produces mux logic and prevents unintended latches.
The [SystemVerilog reading guide](../../00-start-here/reading-systemverilog.md#always_comb-describes-combinational-hardware)
explains the syntax with the SRAM write mux as a worked example.

| Source | What its `always_comb` block(s) implement | Enables or outputs to follow |
|---|---|---|
| `sram_256_wrapper.sv` | Select compute whole-row write or host single-lane write; create eight bank enables | `write_address`, `write_data`, `write_mask[lane]` |
| `descriptor_file.sv` | Select a workspace descriptor or one of three 32-bit words of a matrix descriptor for host readback | `host_is_matrix`, `host_word_sel`, `host_rdata` |
| `matmulfree.sv` | Check overlap with valid dynamic-scale regions; decode one-cycle engine/PC starts; mux one active engine onto workspace; mux one host response region | `input_has_runtime_scale`, `row_start`, `norm_start`, `tm_start`, `pc_*`, `ws_*`, `host_response_data` |
| `rowwise_dispatch.sv` | Validate formats/length/overlap and calculate tail size; map FSM states to workspace reads/writes | `invalid`, `valid_elems`, `ws_rd_en`, `ws_wr_en` |
| `rowwise_op.sv` | Select two lane operands and shared multiplier inputs; insert rounded/saturated lane results into the next packed word | `multiply_a/b`, `lane_valid_q`, `result_buffer_next`, error flags |
| `norm_dispatch.sv` | Reject an invalid source/destination descriptor before the normalization core starts | `invalid`, `start && !invalid`, `rejected` |
| `norm.sv` | Select lane values and shared arithmetic by pass; build divider/sqrt operands; clamp scratch/quantized values; decode FSM into memory and scalar-unit requests | `multiply_a/b`, `arithmetic_shift`, `div_start`, `sqrt_start`, `ws_rd_en`, `ws_wr_en` |
| `ternary_mul.sv` | Calculate packed weight extent; decode each 2-bit weight into `+q/-q/0`; decode FSM into workspace/parameter transactions | `terms[]`, `reserved_weight`, `ws_rd_en`, `param_rd_en`, `ws_wr_en` |
| `scale_compose.sv` | Select the largest fitting shift and apply quotient/remainder RNE after the divider | `selected_shift`, `target_r`, `round_up`, `rounded` |
| `div.sv` | One restoring-division step: shift remainder, trial subtract, and generate the next quotient bit | `rem_shift`, `difference`, `q_next` |
| `isqrt_u64.sv` | One radix-four integer-square-root step: form trial remainder and next root bit | `difference`, `root_next`, `remainder_next` |
| `mul.sv` | Choose signed/unsigned operand interpretation, round and saturate; `addsub` chooses add/sub and detects overflow | `b_s17`, `rounded`, `result`, `overflow` |
| `postscale.sv` | Round the scaled product, add sign-extended bias, select S16/S32 limits, and report saturation | `rounded`, `biased`, `y_s16`, `y_s32`, `overflow` |
| `sigmoid.sv` | Convert fixed-point input to a clamped LUT index plus interpolation fraction | `grid`, `index_next`, `fraction_next` |
| `pipelined_word_ram.sv` | OR-mux the one selected tile response within each static group | `read_tile_q`, `selected`, `group_data_q` capture enable |
| `sigmoid_lut.svh` | Pure case-table lookup of one sigmoid sample | LUT address and sample output; no request/valid state |
| `llm_exp_lut.svh` | Pure case-table lookup of one exponential sample | LUT index and sample output; no request/valid state |
| `llm_gumbel_lut.svh` | Pure case-table lookup of one Gumbel sample | LUT index and sample output; no request/valid state |

For complex rows, use the linked module page rather than reading this table as a
cycle schedule. The combinational block chooses current values; the neighboring
`always_ff` FSM/pipeline determines when those values are captured and become
architecturally visible.

## Controller and graph configuration

| Source | Scope | Role | Notes |
|---|---|---|---|
| [llm_pkg.sv](<../../../Verilog Source code/llm_pkg.sv>) | Full graph | Graph constants/layout/helpers | [llm_pkg.sv guide](llm_pkg.sv.md) |
| [llm_soc.sv](<../../../Verilog Source code/llm_soc.sv>) | Full graph | Top: host, graph, operator control and sampling | [llm_soc.sv guide](llm_soc.sv.md) |

## Compute engines

| Source | Scope | Role | Notes |
|---|---|---|---|
| [llm_attention_engine.sv](<../../../Verilog Source code/llm_attention_engine.sv>) | Full graph | Q/K score according to causal limit and maximum | [llm_attention_engine.sv guide](llm_attention_engine.sv.md) |
| [llm_attention_normalize.sv](<../../../Verilog Source code/llm_attention_normalize.sv>) | Full graph | Exact division, RNE, sign and clamp | [llm_attention_normalize.sv guide](llm_attention_normalize.sv.md) |
| [llm_head_engine.sv](<../../../Verilog Source code/llm_head_engine.sv>) | Full graph | Read four chunks per vocabulary row and accumulate | [llm_head_engine.sv guide](llm_head_engine.sv.md) |
| [llm_linear_engine.sv](<../../../Verilog Source code/llm_linear_engine.sv>) | Full graph | Streaming ternary row and bounded prefetch | [llm_linear_engine.sv guide](llm_linear_engine.sv.md) |
| [llm_math.sv](<../../../Verilog Source code/llm_math.sv>) | Full graph | 32 signed lanes, product and reduction pipeline | [llm_math.sv guide](llm_math.sv.md) |
| [ternary_dot32.sv](<../../../Verilog Source code/ternary_dot32.sv>) | Full graph | 32-term ternary and registered reduction | [ternary_dot32.sv guide](ternary_dot32.sv.md) |

## Memory and reset

| Source | Scope | Role | Notes |
|---|---|---|---|
| [llm_bank_ram.sv](<../../../Verilog Source code/llm_bank_ram.sv>) | Full graph | KV/vector banks with lane mask | [llm_bank_ram.sv guide](llm_bank_ram.sv.md) |
| [llm_parameter_ram.sv](<../../../Verilog Source code/llm_parameter_ram.sv>) | Full graph | Parameter SRAM and host commit | [llm_parameter_ram.sv guide](llm_parameter_ram.sv.md) |
| [reset_release.sv](<../../../Verilog Source code/reset_release.sv>) | Full graph | Reset assertion/release boundary | [reset_release.sv guide](reset_release.sv.md) |
| [pipelined_word_ram.sv](<../../../Verilog Source code/pipelined_word_ram.sv>) | Shared | SRAM request/response pipeline | [pipelined_word_ram.sv guide](pipelined_word_ram.sv.md) |
| [quartus_word_ram.sv](<../../../Verilog Source code/quartus_word_ram.sv>) | Shared | Quartus SRAM technology leaf | [quartus_word_ram.sv guide](quartus_word_ram.sv.md) |
| [sram_word_tile.sv](<../../../Verilog Source code/sram_word_tile.sv>) | Shared | Portable SRAM leaf | [sram_word_tile.sv guide](sram_word_tile.sv.md) |

## Shared arithmetic and LUTs

| Source | Scope | Role | Notes |
|---|---|---|---|
| [llm_exp_lut.svh](<../../../Verilog Source code/llm_exp_lut.svh>) | Full graph | Exponential table for softmax | [llm_exp_lut.svh guide](llm_exp_lut.svh.md) |
| [llm_gumbel_lut.svh](<../../../Verilog Source code/llm_gumbel_lut.svh>) | Full graph | Gumbel table for sampling | [llm_gumbel_lut.svh guide](llm_gumbel_lut.svh.md) |
| [div.sv](<../../../Verilog Source code/div.sv>) | Shared | Unsigned shift/subtract divider | [div.sv guide](div.sv.md) |
| [isqrt_u64.sv](<../../../Verilog Source code/isqrt_u64.sv>) | Shared | Integer sqrt U64 | [isqrt_u64.sv guide](isqrt_u64.sv.md) |
| [logic_mul.sv](<../../../Verilog Source code/logic_mul.sv>) | Shared | Bit-level structure and compressor multiplication | [logic_mul.sv guide](logic_mul.sv.md) |
| [npu_pkg.sv](<../../../Verilog Source code/npu_pkg.sv>) | Shared | Types, saturation, and RNE helpers | [npu_pkg.sv guide](npu_pkg.sv.md) |
| [sigmoid.sv](<../../../Verilog Source code/sigmoid.sv>) | Shared | Sigmoid ROM/interpolation | [sigmoid.sv guide](sigmoid.sv.md) |
| [sigmoid_lut.svh](<../../../Verilog Source code/sigmoid_lut.svh>) | Shared | Constant sigmoid ROM | [sigmoid_lut.svh guide](sigmoid_lut.svh.md) |

## Legacy core

| Source | Scope | Role | Notes |
|---|---|---|---|
| [acc_mul.sv](<../../../Verilog Source code/acc_mul.sv>) | Legacy | Sum ternary terms | [acc_mul.sv guide](acc_mul.sv.md) |
| [banked_word_ram.sv](<../../../Verilog Source code/banked_word_ram.sv>) | Legacy | Tile/mux wrapper | [banked_word_ram.sv guide](banked_word_ram.sv.md) |
| [descriptor_file.sv](<../../../Verilog Source code/descriptor_file.sv>) | Legacy | Tensor/matrix descriptors | [descriptor_file.sv guide](descriptor_file.sv.md) |
| [ins_mem.sv](<../../../Verilog Source code/ins_mem.sv>) | Legacy | Instruction memory | [ins_mem.sv guide](ins_mem.sv.md) |
| [matmul_wrap.sv](<../../../Verilog Source code/matmul_wrap.sv>) | Legacy | Wrapper top clock/reset/LED | [matmul_wrap.sv guide](matmul_wrap.sv.md) |
| [matmulfree.sv](<../../../Verilog Source code/matmulfree.sv>) | Legacy | Top instruction-driven | [matmulfree.sv guide](matmulfree.sv.md) |
| [mem_mapping.sv](<../../../Verilog Source code/mem_mapping.sv>) | Legacy | Parameter memory wrapper | [mem_mapping.sv guide](mem_mapping.sv.md) |
| [norm.sv](<../../../Verilog Source code/norm.sv>) | Legacy | RMSNorm/QUANT; sqrt is in a separate file | [norm.sv guide](norm.sv.md) |
| [norm_dispatch.sv](<../../../Verilog Source code/norm_dispatch.sv>) | Legacy | Descriptor validation for norm | [norm_dispatch.sv guide](norm_dispatch.sv.md) |
| [PC.sv](<../../../Verilog Source code/PC.sv>) | Legacy | Program counter | [PC.sv guide](PC.sv.md) |
| [postscale.sv](<../../../Verilog Source code/postscale.sv>) | Legacy | Scale/bias after accumulator | [postscale.sv guide](postscale.sv.md) |
| [regfile.sv](<../../../Verilog Source code/regfile.sv>) | Legacy | Workspace memory wrapper | [regfile.sv guide](regfile.sv.md) |
| [rowwise_dispatch.sv](<../../../Verilog Source code/rowwise_dispatch.sv>) | Legacy | Vector operation dispatcher | [rowwise_dispatch.sv guide](rowwise_dispatch.sv.md) |
| [rowwise_op.sv](<../../../Verilog Source code/rowwise_op.sv>) | Legacy | Vector datapath | [rowwise_op.sv guide](rowwise_op.sv.md) |
| [scale_compose.sv](<../../../Verilog Source code/scale_compose.sv>) | Legacy | Dynamic scale composition | [scale_compose.sv guide](scale_compose.sv.md) |
| [sram_256_wrapper.sv](<../../../Verilog Source code/sram_256_wrapper.sv>) | Legacy | 256-bit SRAM wrapper | [sram_256_wrapper.sv guide](sram_256_wrapper.sv.md) |
| [ternary_mul.sv](<../../../Verilog Source code/ternary_mul.sv>) | Legacy | TMATMUL core | [ternary_mul.sv guide](ternary_mul.sv.md) |

## Helpers and reference assets

| Source | Scope | Role | Notes |
|---|---|---|---|
| [mul.sv](<../../../Verilog Source code/mul.sv>) | Helper | Signed scalar helper, not part of full-top llm_soc | [mul.sv guide](mul.sv.md) |
| [sigmoid_257.mem](<../../../Verilog Source code/sigmoid_257.mem>) | Asset | Reference/generate sigmoid table | [sigmoid_257.mem guide](sigmoid_257.mem.md) |
