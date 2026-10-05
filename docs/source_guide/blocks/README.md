# Danh mục RTL và chú giải hiện tại

[Tài liệu](../../README.md) → **Source guide**

Bắt đầu với [full graph overview](../full_graph.md) cho top llm_soc.
[Hierarchy legacy](../README.md) giải thích core matmulfree và mô tả core legacy bằng các sơ đồ đã đối chiếu source hiện tại.

## Cách dùng danh mục

Cột **Source hiện tại** dẫn tới RTL đang compile. **Chú giải hiện tại** cung cấp sơ đồ và code excerpts khớp source_manifest.json ngày 06/10/2026. Hash xác nhận source; regression và timing có evidence riêng.

## Toàn bộ source và LUT

| Source hiện tại | Phạm vi | Vai trò | Chú giải hiện tại | So với source hiện tại |
|---|---|---|---|---|
| [llm_attention_engine.sv](<../../../Verilog Source code/llm_attention_engine.sv>) | Full graph | Score Q/K theo giới hạn causal và maximum | [Xem chú giải](llm_attention_engine.sv.md) | Khớp hash |
| [llm_attention_normalize.sv](<../../../Verilog Source code/llm_attention_normalize.sv>) | Full graph | Exact division, RNE, sign và clamp | [Xem chú giải](llm_attention_normalize.sv.md) | Khớp hash |
| [llm_bank_ram.sv](<../../../Verilog Source code/llm_bank_ram.sv>) | Full graph | KV/vector banks với lane mask | [Xem chú giải](llm_bank_ram.sv.md) | Khớp hash |
| [llm_exp_lut.svh](<../../../Verilog Source code/llm_exp_lut.svh>) | Full graph | Bảng exp cho softmax | [Xem chú giải](llm_exp_lut.svh.md) | Khớp hash |
| [llm_gumbel_lut.svh](<../../../Verilog Source code/llm_gumbel_lut.svh>) | Full graph | Bảng Gumbel cho sampling | [Xem chú giải](llm_gumbel_lut.svh.md) | Khớp hash |
| [llm_head_engine.sv](<../../../Verilog Source code/llm_head_engine.sv>) | Full graph | Đọc bốn chunk mỗi hàng vocabulary và tích lũy | [Xem chú giải](llm_head_engine.sv.md) | Khớp hash |
| [llm_linear_engine.sv](<../../../Verilog Source code/llm_linear_engine.sv>) | Full graph | Streaming ternary row và bounded prefetch | [Xem chú giải](llm_linear_engine.sv.md) | Khớp hash |
| [llm_math.sv](<../../../Verilog Source code/llm_math.sv>) | Full graph | 32 signed lanes, product và reduction pipeline | [Xem chú giải](llm_math.sv.md) | Khớp hash |
| [llm_parameter_ram.sv](<../../../Verilog Source code/llm_parameter_ram.sv>) | Full graph | Parameter SRAM và host commit | [Xem chú giải](llm_parameter_ram.sv.md) | Khớp hash |
| [llm_pkg.sv](<../../../Verilog Source code/llm_pkg.sv>) | Full graph | Constants/layout/helper của graph | [Xem chú giải](llm_pkg.sv.md) | Khớp hash |
| [llm_soc.sv](<../../../Verilog Source code/llm_soc.sv>) | Full graph | Top: host, graph, operator control và sampling | [Xem chú giải](llm_soc.sv.md) | Khớp hash |
| [reset_release.sv](<../../../Verilog Source code/reset_release.sv>) | Full graph | Reset assertion/release boundary | [Xem chú giải](reset_release.sv.md) | Khớp hash |
| [ternary_dot32.sv](<../../../Verilog Source code/ternary_dot32.sv>) | Full graph | 32 term ternary và registered reduction | [Xem chú giải](ternary_dot32.sv.md) | Khớp hash |
| [div.sv](<../../../Verilog Source code/div.sv>) | Dùng chung | Unsigned shift/subtract divider | [Xem chú giải](div.sv.md) | Khớp hash |
| [isqrt_u64.sv](<../../../Verilog Source code/isqrt_u64.sv>) | Dùng chung | Integer sqrt U64 | [Xem chú giải](isqrt_u64.sv.md) | Khớp hash |
| [logic_mul.sv](<../../../Verilog Source code/logic_mul.sv>) | Dùng chung | Nhân bằng cấu trúc bit và compressor | [Xem chú giải](logic_mul.sv.md) | Khớp hash |
| [npu_pkg.sv](<../../../Verilog Source code/npu_pkg.sv>) | Dùng chung | Types, saturation và RNE helpers | [Xem chú giải](npu_pkg.sv.md) | Khớp hash |
| [pipelined_word_ram.sv](<../../../Verilog Source code/pipelined_word_ram.sv>) | Dùng chung | SRAM request/response pipeline | [Xem chú giải](pipelined_word_ram.sv.md) | Khớp hash |
| [quartus_word_ram.sv](<../../../Verilog Source code/quartus_word_ram.sv>) | Dùng chung | SRAM technology leaf Quartus | [Xem chú giải](quartus_word_ram.sv.md) | Khớp hash |
| [sigmoid.sv](<../../../Verilog Source code/sigmoid.sv>) | Dùng chung | Sigmoid ROM/interpolation | [Xem chú giải](sigmoid.sv.md) | Khớp hash |
| [sigmoid_lut.svh](<../../../Verilog Source code/sigmoid_lut.svh>) | Dùng chung | Constant sigmoid ROM | [Xem chú giải](sigmoid_lut.svh.md) | Khớp hash |
| [sram_word_tile.sv](<../../../Verilog Source code/sram_word_tile.sv>) | Dùng chung | Portable SRAM leaf | [Xem chú giải](sram_word_tile.sv.md) | Khớp hash |
| [acc_mul.sv](<../../../Verilog Source code/acc_mul.sv>) | Legacy | Cộng ternary terms | [Xem chú giải](acc_mul.sv.md) | Khớp hash |
| [banked_word_ram.sv](<../../../Verilog Source code/banked_word_ram.sv>) | Legacy | Tile/mux wrapper | [Xem chú giải](banked_word_ram.sv.md) | Khớp hash |
| [descriptor_file.sv](<../../../Verilog Source code/descriptor_file.sv>) | Legacy | Tensor/matrix descriptors | [Xem chú giải](descriptor_file.sv.md) | Khớp hash |
| [ins_mem.sv](<../../../Verilog Source code/ins_mem.sv>) | Legacy | Instruction memory | [Xem chú giải](ins_mem.sv.md) | Khớp hash |
| [matmul_wrap.sv](<../../../Verilog Source code/matmul_wrap.sv>) | Legacy | Wrapper top clock/reset/LED | [Xem chú giải](matmul_wrap.sv.md) | Khớp hash |
| [matmulfree.sv](<../../../Verilog Source code/matmulfree.sv>) | Legacy | Top instruction-driven | [Xem chú giải](matmulfree.sv.md) | Khớp hash |
| [mem_mapping.sv](<../../../Verilog Source code/mem_mapping.sv>) | Legacy | Parameter memory wrapper | [Xem chú giải](mem_mapping.sv.md) | Khớp hash |
| [norm.sv](<../../../Verilog Source code/norm.sv>) | Legacy | RMSNorm/QUANT; sqrt đã ở file riêng | [Xem chú giải](norm.sv.md) | Khớp hash |
| [norm_dispatch.sv](<../../../Verilog Source code/norm_dispatch.sv>) | Legacy | Descriptor validation cho norm | [Xem chú giải](norm_dispatch.sv.md) | Khớp hash |
| [PC.sv](<../../../Verilog Source code/PC.sv>) | Legacy | Program counter | [Xem chú giải](PC.sv.md) | Khớp hash |
| [postscale.sv](<../../../Verilog Source code/postscale.sv>) | Legacy | Scale/bias sau accumulator | [Xem chú giải](postscale.sv.md) | Khớp hash |
| [regfile.sv](<../../../Verilog Source code/regfile.sv>) | Legacy | Workspace memory wrapper | [Xem chú giải](regfile.sv.md) | Khớp hash |
| [rowwise_dispatch.sv](<../../../Verilog Source code/rowwise_dispatch.sv>) | Legacy | Điều phối vector operation | [Xem chú giải](rowwise_dispatch.sv.md) | Khớp hash |
| [rowwise_op.sv](<../../../Verilog Source code/rowwise_op.sv>) | Legacy | Vector datapath | [Xem chú giải](rowwise_op.sv.md) | Khớp hash |
| [scale_compose.sv](<../../../Verilog Source code/scale_compose.sv>) | Legacy | Dynamic scale composition | [Xem chú giải](scale_compose.sv.md) | Khớp hash |
| [sram_256_wrapper.sv](<../../../Verilog Source code/sram_256_wrapper.sv>) | Legacy | Wrapper SRAM 256 bit | [Xem chú giải](sram_256_wrapper.sv.md) | Khớp hash |
| [ternary_mul.sv](<../../../Verilog Source code/ternary_mul.sv>) | Legacy | TMATMUL core | [Xem chú giải](ternary_mul.sv.md) | Khớp hash |
| [mul.sv](<../../../Verilog Source code/mul.sv>) | Helper | Signed scalar helper, không thuộc full-top llm_soc | [Xem chú giải](mul.sv.md) | Khớp hash |
| [sigmoid_257.mem](<../../../Verilog Source code/sigmoid_257.mem>) | Asset | Đối chiếu/generate sigmoid table | [Xem chú giải](sigmoid_257.mem.md) | Khớp hash |

## Phạm vi cập nhật

Danh mục này bao phủ 41 RTL/LUT assets hiện tại. Nội dung prose, mục lục và
source links được cập nhật ngày 06/10/2026. Sơ đồ, source_manifest và code excerpts đã được đối chiếu lại với source hiện tại.

[Trạng thái kiểm chứng](../../verification/optimization_status.md) ·
[Hướng dẫn đọc RTL](../full_graph.md) · [Quy tắc RTL](../../design/rtl_style.md)
