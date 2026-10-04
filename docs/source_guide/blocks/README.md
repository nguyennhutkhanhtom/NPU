# Mục lục giải thích từng file

[Tài liệu](../../README.md) → [Hierarchy RTL](../README.md) → **Mục lục từng file**

Mỗi trang gồm vai trò, sơ đồ kiến trúc tổng quan, phần giải thích hoạt động và source được gom theo nhóm logic. Hình cạnh các nhóm code cũng mô tả khối phần cứng và kết nối, không mô tả FSM, timing hay pipeline CPU. Package được trình bày như quan hệ định nghĩa RTL; legacy/helper có sơ đồ độc lập và không thuộc hierarchy NPU hiện tại.

| File | Vai trò | Trạng thái | Nhóm logic | Số dòng |
|---|---|---|---:|---:|
| [reset_release.sv](reset_release.sv.md) | Standard-FF reset release boundary | Full RTL graph | 3 | 15 |
| [logic_mul.sv](logic_mul.sv.md) | Portable bit-product compressor tree | Full RTL graph | 4 | 74 |
| [quartus_word_ram.sv](quartus_word_ram.sv.md) | FPGA memory technology binding | Full RTL graph | 3 | 39 |
| [pipelined_word_ram.sv](pipelined_word_ram.sv.md) | Tile request và response pipeline | Full RTL graph | 3 | 114 |
| [llm_parameter_ram.sv](llm_parameter_ram.sv.md) | Parameter SRAM và host commit | Full RTL graph | 4 | 95 |
| [llm_soc.sv](llm_soc.sv.md) | Autonomous autoregressive graph | Full RTL graph | 11 | 1031 |
| [llm_pkg.sv](llm_pkg.sv.md) | Layout, saturation và sampler | Full RTL graph | 3 | 31 |
| [llm_math.sv](llm_math.sv.md) | SIMD signed multiply và reduction | Full RTL graph | 5 | 72 |
| [llm_gumbel_lut.svh](llm_gumbel_lut.svh.md) | LUT portable của graph | Full RTL graph | — | 267 |
| [llm_exp_lut.svh](llm_exp_lut.svh.md) | LUT portable của graph | Full RTL graph | — | 268 |
| [llm_bank_ram.sv](llm_bank_ram.sv.md) | SRAM lane-masked cho graph | Full RTL graph | 3 | 76 |
| [banked_word_ram.sv](banked_word_ram.sv.md) | SRAM tiles và mux đọc | Full RTL graph | 4 | 55 |
| [matmulfree.sv](matmulfree.sv.md) | Top-level: điều phối toàn NPU | Đang dùng — core chính | 15 | 572 |
| [npu_pkg.sv](npu_pkg.sv.md) | Kiểu dữ liệu, saturation và RNE S64/S42 | Đang dùng — package chung | 7 | 128 |
| [norm.sv](norm.sv.md) | RMSNorm toàn vector và QUANT | Đang dùng — chứa norm và isqrt_u64 | 17 | 617 |
| [ternary_mul.sv](ternary_mul.sv.md) | 32 PE ternary và vòng lặp dot product | Đang dùng — TMATMUL | 9 | 309 |
| [rowwise_op.sv](rowwise_op.sv.md) | ALU vector nhỏ và cập nhật state | Đang dùng — datapath rowwise | 9 | 248 |
| [rowwise_dispatch.sv](rowwise_dispatch.sv.md) | Đọc tensor, gọi ALU và ghi output | Đang dùng — điều phối rowwise | 8 | 166 |
| [scale_compose.sv](scale_compose.sv.md) | Ghép scale động của q vào postscale | Đang dùng — trước TMATMUL dynamic_q | 6 | 154 |
| [sigmoid.sv](sigmoid.sv.md) | Sigmoid bằng ROM và nội suy | Đang dùng — gọi từ rowwise_op | 3 | 106 |
| [sram_256_wrapper.sv](sram_256_wrapper.sv.md) | Ranh giới giữa RTL và SRAM macro | Đang dùng — chung cho hai SRAM | 5 | 101 |
| [descriptor_file.sv](descriptor_file.sv.md) | Bảng mô tả tensor và ma trận | Đang dùng | 3 | 70 |
| [div.sv](div.sv.md) | Divider unsigned tuần tự | Đang dùng — scalar nội bộ | 4 | 72 |
| [acc_mul.sv](acc_mul.sv.md) | Cây cộng 32 term ternary | Đang dùng — trong ternary_mul | 2 | 31 |
| [postscale.sv](postscale.sv.md) | Postscale wrapper và bias finish | Đang dùng — sau accumulator | 2 | 46 |
| [norm_dispatch.sv](norm_dispatch.sv.md) | Kiểm tra descriptor trước NORM | Đang dùng | 3 | 72 |
| [regfile.sv](regfile.sv.md) | Wrapper SRAM 8 KiB | Đang dùng | 2 | 40 |
| [mem_mapping.sv](mem_mapping.sv.md) | Wrapper SRAM 32 KiB | Đang dùng | 2 | 40 |
| [PC.sv](PC.sv.md) | Program counter | Đang dùng | 2 | 16 |
| [ins_mem.sv](ins_mem.sv.md) | Instruction memory do host nạp | Đang dùng | 4 | 61 |
| [matmul_wrap.sv](matmul_wrap.sv.md) | Wrapper clock/reset/LED | Đang dùng nếu chọn board top | 2 | 29 |
| [mul.sv](mul.sv.md) | Helper nhân S16 và gate | Helper — không instantiate trong top hiện tại | 2 | 43 |
| [sigmoid_lut.svh](sigmoid_lut.svh.md) | LUT — giải thích mỗi entry | Đang dùng — ROM hằng trong RTL | — | 267 |
| [sigmoid_257.mem](sigmoid_257.mem.md) | LUT — giải thích mỗi entry | Asset đối chiếu cho generator/test | 0 | 257 |

## Các file không phải source đang chạy

Các backup `.bak` và LUT v1 đã được loại bỏ khi dọn workspace vì không tham gia datapath hiện tại. README của source là tài liệu cấu hình, đã được đối chiếu trong trang tổng quan. Testbench/generator thuộc verification, không phải block trong NPU.
