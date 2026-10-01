# Mục lục giải thích từng file

[Tài liệu](../../README.md) → [Hierarchy RTL](../README.md) → **Mục lục từng file**

Mỗi trang gồm vai trò, sơ đồ kiến trúc tổng quan, phần giải thích hoạt động và source được gom theo nhóm logic. Hình cạnh các nhóm code cũng mô tả khối phần cứng và kết nối, không mô tả FSM, timing hay pipeline CPU. Package được trình bày như quan hệ định nghĩa RTL; legacy/helper có sơ đồ độc lập và không thuộc hierarchy NPU hiện tại.

| File | Vai trò | Trạng thái | Nhóm logic | Số dòng |
|---|---|---|---:|---:|
| [matmulfree.sv](matmulfree.sv.md) | Top-level: điều phối toàn NPU | Đang dùng — core chính | 15 | 517 |
| [npu_pkg.sv](npu_pkg.sv.md) | Kiểu dữ liệu, saturation và rounding | Đang dùng — package chung | 6 | 110 |
| [norm.sv](norm.sv.md) | RMSNorm toàn vector và QUANT | Đang dùng — chứa norm và isqrt_u64 | 17 | 580 |
| [ternary_mul.sv](ternary_mul.sv.md) | 32 PE ternary và vòng lặp dot product | Đang dùng — TMATMUL | 9 | 266 |
| [rowwise_op.sv](rowwise_op.sv.md) | ALU vector nhỏ và cập nhật state | Đang dùng — datapath rowwise | 9 | 193 |
| [rowwise_dispatch.sv](rowwise_dispatch.sv.md) | Đọc tensor, gọi ALU và ghi output | Đang dùng — điều phối rowwise | 8 | 166 |
| [scale_compose.sv](scale_compose.sv.md) | Ghép scale động của q vào postscale | Đang dùng — trước TMATMUL dynamic_q | 6 | 144 |
| [sigmoid.sv](sigmoid.sv.md) | Sigmoid bằng ROM và nội suy | Đang dùng — gọi từ rowwise_op | 3 | 90 |
| [sram_256_wrapper.sv](sram_256_wrapper.sv.md) | Ranh giới giữa RTL và SRAM macro | Đang dùng — chung cho hai SRAM | 5 | 104 |
| [descriptor_file.sv](descriptor_file.sv.md) | Bảng mô tả tensor và ma trận | Đang dùng | 3 | 70 |
| [div.sv](div.sv.md) | Divider unsigned tuần tự | Đang dùng — scalar nội bộ | 4 | 68 |
| [acc_mul.sv](acc_mul.sv.md) | Cây cộng 32 term ternary | Đang dùng — trong ternary_mul | 2 | 19 |
| [postscale.sv](postscale.sv.md) | Đổi scale, cộng bias và saturation | Đang dùng — sau accumulator | 2 | 24 |
| [norm_dispatch.sv](norm_dispatch.sv.md) | Kiểm tra descriptor trước NORM | Đang dùng | 3 | 72 |
| [regfile.sv](regfile.sv.md) | Wrapper SRAM 8 KiB | Đang dùng | 2 | 40 |
| [mem_mapping.sv](mem_mapping.sv.md) | Wrapper SRAM 32 KiB | Đang dùng | 2 | 40 |
| [PC.sv](PC.sv.md) | Program counter | Đang dùng | 2 | 16 |
| [ins_mem.sv](ins_mem.sv.md) | Instruction memory do host nạp | Đang dùng | 4 | 61 |
| [matmul_wrap.sv](matmul_wrap.sv.md) | Wrapper clock/reset/LED | Đang dùng nếu chọn board top | 2 | 29 |
| [addsub.sv](addsub.sv.md) | Helper cộng/trừ có saturation | Helper — không instantiate trong top hiện tại | 2 | 17 |
| [mul.sv](mul.sv.md) | Helper nhân S16 và gate | Helper — không instantiate trong top hiện tại | 2 | 22 |
| [fd_reg.sv](fd_reg.sv.md) | Pipeline register Fetch → Decode | Legacy — không nối vào matmulfree hiện tại | 1 | 12 |
| [de_reg.sv](de_reg.sv.md) | Pipeline register Decode → Execute | Legacy — không nối vào matmulfree hiện tại | 1 | 16 |
| [em_reg.sv](em_reg.sv.md) | Pipeline register Execute → Memory | Legacy — không nối vào matmulfree hiện tại | 1 | 10 |
| [mw_reg.sv](mw_reg.sv.md) | Pipeline register Memory → Write Back | Legacy — không nối vào matmulfree hiện tại | 1 | 10 |
| [ctrl_unit.sv](ctrl_unit.sv.md) | Decoder giữ lại từ cấu trúc cũ | Legacy — không dùng trong scheduler v2 | 2 | 23 |
| [hazard_detect.sv](hazard_detect.sv.md) | Control stall/flush kiểu cũ | Legacy — không dùng trong top hiện tại | 1 | 12 |
| [exp.sv](exp.sv.md) | EXP stub | Legacy — không phải exp có thể sử dụng | 1 | 8 |
| [mem_burst.v](mem_burst.v.md) | Adapter burst cho memory ngoài kiểu FPGA | Legacy — không instantiate trong ASIC core hiện tại | 7 | 247 |
| [sigmoid_lut.svh](sigmoid_lut.svh.md) | LUT — giải thích mỗi entry | Đang dùng — ROM hằng trong RTL | — | 262 |
| [sigmoid_257.mem](sigmoid_257.mem.md) | LUT — giải thích mỗi entry | Asset đối chiếu cho generator/test | — | 257 |

## Các file không phải source đang chạy

Các backup `.bak` và LUT v1 đã được loại bỏ khi dọn workspace vì không tham gia datapath hiện tại. README của source là tài liệu cấu hình, đã được đối chiếu trong trang tổng quan. Testbench/generator thuộc verification, không phải block trong NPU.
