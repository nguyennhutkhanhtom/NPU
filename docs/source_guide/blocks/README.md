# Guide source by module

<!-- reading-navigation:start -->
[Documentation](../../README.md) → [02 · Architecture](../../02-architecture/README.md) → Module catalog

| Reading guide | Document |
|---|---|
| New to the subject | [NPU and RTL fundamentals](../../00-start-here/fundamentals.md) · [Glossary](../../00-start-here/glossary.md) |
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
