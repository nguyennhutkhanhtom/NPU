# Guide source by module

> **Category: GUIDE.** Read [full graph](../full_graph.md) first; [hierarchy legacy](../legacy/README.md) describes `matmulfree`.

The source links point to the current implementation. The annotation describes the responsibility
tasks and contracts without copying RTL. The diagram follows the [shared visual style](../../diagrams/diagram_style.md).

| Source | Scope | Role | Notes |
|---|---|---|---|
| [llm_attention_engine.sv](<../../../Verilog Source code/llm_attention_engine.sv>) | Full graph | Q/K score according to causal limit and maximum | [View legend](llm_attention_engine.sv.md) |
| [llm_attention_normalize.sv](<../../../Verilog Source code/llm_attention_normalize.sv>) | Full graph | Exact division, RNE, sign and clamp | [View annotation](llm_attention_normalize.sv.md) |
| [llm_bank_ram.sv](<../../../Verilog Source code/llm_bank_ram.sv>) | Full graph | KV/vector banks with lane mask | [View annotation](llm_bank_ram.sv.md) |
| [llm_exp_lut.svh](<../../../Verilog Source code/llm_exp_lut.svh>) | Full graph | Exponential table for softmax | [View annotation](llm_exp_lut.svh.md) |
| [llm_gumbel_lut.svh](<../../../Verilog Source code/llm_gumbel_lut.svh>) | Full graph | Gumbel table for sampling | [View annotation](llm_gumbel_lut.svh.md) |
| [llm_head_engine.sv](<../../../Verilog Source code/llm_head_engine.sv>) | Full graph | Read four chunks per vocabulary row and accumulate | [View notes](llm_head_engine.sv.md) |
| [llm_linear_engine.sv](<../../../Verilog Source code/llm_linear_engine.sv>) | Full graph | Streaming ternary row and bounded prefetch | [View notes](llm_linear_engine.sv.md) |
| [llm_math.sv](<../../../Verilog Source code/llm_math.sv>) | Full graph | 32 signed lanes, product and reduction pipeline | [View notes](llm_math.sv.md) |
| [llm_parameter_ram.sv](<../../../Verilog Source code/llm_parameter_ram.sv>) | Full graph | Parameter SRAM and host commit | [View notes](llm_parameter_ram.sv.md) |
| [llm_pkg.sv](<../../../Verilog Source code/llm_pkg.sv>) | Full graph | Graph constants/layout/helpers | [View annotation](llm_pkg.sv.md) |
| [llm_soc.sv](<../../../Verilog Source code/llm_soc.sv>) | Full graph | Top: host, graph, operator control and sampling | [View annotation](llm_soc.sv.md) |
| [reset_release.sv](<../../../Verilog Source code/reset_release.sv>) | Full graph | Reset assertion/release boundary | [View annotation](reset_release.sv.md) |
| [ternary_dot32.sv](<../../../Verilog Source code/ternary_dot32.sv>) | Full graph | 32-term ternary and registered reduction | [View annotation](ternary_dot32.sv.md) |
| [div.sv](<../../../Verilog Source code/div.sv>) | Shared | Unsigned shift/subtract divider | [View notes](div.sv.md) |
| [isqrt_u64.sv](<../../../Verilog Source code/isqrt_u64.sv>) | Shared | Integer sqrt U64 | [View notes](isqrt_u64.sv.md) |
| [logic_mul.sv](<../../../Verilog Source code/logic_mul.sv>) | Shared | Bit-level structure and compressor multiplication | [View notes](logic_mul.sv.md) |
| [npu_pkg.sv](<../../../Verilog Source code/npu_pkg.sv>) | Shared | Types, saturation, and RNE helpers | [View notes](npu_pkg.sv.md) |
| [pipelined_word_ram.sv](<../../../Verilog Source code/pipelined_word_ram.sv>) | Shared | SRAM request/response pipeline | [View notes](pipelined_word_ram.sv.md) |
| [quartus_word_ram.sv](<../../../Verilog Source code/quartus_word_ram.sv>) | Shared | Quartus SRAM technology leaf | [View notes](quartus_word_ram.sv.md) |
| [sigmoid.sv](<../../../Verilog Source code/sigmoid.sv>) | Shared | Sigmoid ROM/interpolation | [View notes](sigmoid.sv.md) |
| [sigmoid_lut.svh](<../../../Verilog Source code/sigmoid_lut.svh>) | Shared | Constant sigmoid ROM | [View notes](sigmoid_lut.svh.md) |
| [sram_word_tile.sv](<../../../Verilog Source code/sram_word_tile.sv>) | Shared | Portable SRAM leaf | [View notes](sram_word_tile.sv.md) |
| [acc_mul.sv](<../../../Verilog Source code/acc_mul.sv>) | Legacy | Sum ternary terms | [View notes](acc_mul.sv.md) |
| [banked_word_ram.sv](<../../../Verilog Source code/banked_word_ram.sv>) | Legacy | Tile/mux wrapper | [View notes](banked_word_ram.sv.md) |
| [descriptor_file.sv](<../../../Verilog Source code/descriptor_file.sv>) | Legacy | Tensor/matrix descriptors | [View notes](descriptor_file.sv.md) |
| [ins_mem.sv](<../../../Verilog Source code/ins_mem.sv>) | Legacy | Instruction memory | [View notes](ins_mem.sv.md) |
| [matmul_wrap.sv](<../../../Verilog Source code/matmul_wrap.sv>) | Legacy | Wrapper top clock/reset/LED | [View notes](matmul_wrap.sv.md) |
| [matmulfree.sv](<../../../Verilog Source code/matmulfree.sv>) | Legacy | Top instruction-driven | [View notes](matmulfree.sv.md) |
| [mem_mapping.sv](<../../../Verilog Source code/mem_mapping.sv>) | Legacy | Parameter memory wrapper | [See annotation](mem_mapping.sv.md) |
| [norm.sv](<../../../Verilog Source code/norm.sv>) | Legacy | RMSNorm/QUANT; sqrt is in a separate file | [See annotation](norm.sv.md) |
| [norm_dispatch.sv](<../../../Verilog Source code/norm_dispatch.sv>) | Legacy | Descriptor validation for norm | [See annotation](norm_dispatch.sv.md) |
| [PC.sv](<../../../Verilog Source code/PC.sv>) | Legacy | Program counter | [See annotation](PC.sv.md) |
| [postscale.sv](<../../../Verilog Source code/postscale.sv>) | Legacy | Scale/bias after accumulator | [See annotation](postscale.sv.md) |
| [regfile.sv](<../../../Verilog Source code/regfile.sv>) | Legacy | Workspace memory wrapper | [View annotation](regfile.sv.md) |
| [rowwise_dispatch.sv](<../../../Verilog Source code/rowwise_dispatch.sv>) | Legacy | Vector operation dispatcher | [View annotation](rowwise_dispatch.sv.md) |
| [rowwise_op.sv](<../../../Verilog Source code/rowwise_op.sv>) | Legacy | Vector datapath | [View annotation](rowwise_op.sv.md) |
| [scale_compose.sv](<../../../Verilog Source code/scale_compose.sv>) | Legacy | Dynamic scale composition | [View annotation](scale_compose.sv.md) |
| [sram_256_wrapper.sv](<../../../Verilog Source code/sram_256_wrapper.sv>) | Legacy | 256-bit SRAM wrapper | [View annotation](sram_256_wrapper.sv.md) |
| [ternary_mul.sv](<../../../Verilog Source code/ternary_mul.sv>) | Legacy | TMATMUL core | [View annotation](ternary_mul.sv.md) |
| [mul.sv](<../../../Verilog Source code/mul.sv>) | Helper | Signed scalar helper, not part of full-top llm_soc | [View annotation](mul.sv.md) |
| [sigmoid_257.mem](<../../../Verilog Source code/sigmoid_257.mem>) | Asset | Reference/generate sigmoid table | [View annotation](sigmoid_257.mem.md) |
