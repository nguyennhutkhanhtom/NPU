# Hệ thống tests

> **Category: GUIDE.**

[Trang bắt đầu](../README.md) · [Mục lục tài liệu](../docs/README.md) · [Kết quả kiểm chứng](../docs/verification/README.md) · [Các demo model](../docs/demos/README.md)

## Chọn bộ kiểm chứng

| Thiết kế | Entry point trên Linux Slurm | Hướng dẫn |
|---|---|---|
| llm_soc units/graph/probes | `tools/server/run_flow.py --stage test` | [Flow server](../tools/server/README.md) |
| llm_soc checkpoint | `--stage application --fixture PATH` | [Flow server](../tools/server/README.md#application-checkpoint) |
| matmulfree legacy | `--stage legacy` | [Flow server](../tools/server/README.md) |

## Regression legacy

Runner legacy compile cùng thư mục Verilog Source code và dùng tb_all.sv.
Kết quả của bộ này thuộc core matmulfree; full graph llm_soc có bảy nhóm riêng.

Xcelium chạy các top trong `tb_all.sv`; Python integer/Decimal sinh vectors
trong database riêng của từng top. Không cần tool test local. Chọn danh sách
legacy tops trong `tools/server/flow.json`; runner hiện tại chạy 9 top đầy đủ.
Các block/coverage bên dưới là contract của fixtures được giữ nguyên.

| Block | Nội dung |
|---|---|
| All | Tám testbench trên cùng một RTL và kiểm tra ROM bằng Python |
| Host | Toàn bộ 168 ca tích hợp qua host: NORM, TMATMUL, vector, scale động, descriptor và địa chỉ |
| Norm | NORM/QUANT, K=1…512, packing/tail, zero/full-scale, epsilon/delta, overlap và bounds |
| Ternary | Weight theo chunk, S8 extrema, bias/no-bias, S16/S32, NORM→TMATMUL, scale bị vô hiệu và descriptor sai |
| Rowwise | ADD/SUB/MUL/SIG/REC/RELU, shift, RNE, saturation, gate unsigned, tail và overlap |
| Scalar | Divider U64, sqrt 0…4095 và biên square±1, RNE, exact scale composition U128, reset/start khi busy |
| DivProfiles | NUM/DEN=1/1, 7/3, 3/7, 64/32, 64/64; exhaustive widths nhỏ, quotient/remainder, zero và input capture |
| Postscale | ACC18×U24, RNE shift 0…63, bias S32, saturation S16/S32, extrema và random |
| Sigmoid | 1.638.400 giá trị S16 cho đủ F=0…24 qua ROM constant trong `sigmoid_lut.svh`; reset/start khi busy |
| Sram | 47 kiểm tra latency hai clock, chuyển địa chỉ, mask lane, compute read và reset giữ memory |
| Imem | 1.027 checks: 512 địa chỉ, client switch, synchronous valid, overwrite/re-read, restart/reset |
| Arithmetic | Reduction tree, helper addsub/mul, biên và random |
| AccMul / AddSub / Mul | Chọn task số học riêng trong `tb_arithmetic` |

Mỗi top có database/log riêng trong `build/TAG` và `reports/TAG`.

`reference.py` tạo lại vector bằng Python integer/Decimal và kiểm tra chính xác 257 sample của cả `.mem` và `.svh`, bao gồm monotonic và chênh lệch hai sample liên tiếp không quá 512. Nó còn kiểm tra validator từ chối từng asset bị thiếu hoặc sai sample 128: hai ca thiếu và hai ca hỏng, bằng input mô phỏng trong Python. RTL luôn dùng ROM constant, không có tham số thay file LUT.

Scale composition được so sánh cả `(M,r)` với phép chia/làm tròn U128 độc lập, tìm `r` lớn nhất trong 0…47. Cases phủ underflow/overflow, giới hạn RNE của U24, midpoint và hai phía của midpoint; transaction hợp lệ phải hoàn tất trong 128 clock. Sqrt kiểm tra `root² ≤ x < (root+1)²` bằng tích U66 và latency 32 clock. Các test còn thay input/pulse `start` khi busy và reset giữa transaction để kiểm tra capture/cancel/restart.

Host cases thêm NORM overflow rồi descriptor sai không reset (overflow mới phải bằng 0 và output giữ nguyên), reset trong lúc divider NORM busy rồi restart, cùng/partial alias của NORM q bị từ chối nếu dùng scale static và địa chỉ ngay sau q extent vẫn hợp lệ.

Synthesis hiện tại dùng Genus cho `llm_soc` và Liberty do lab cung cấp.
`check_synthesis.tcl` và runner PowerShell cũ trả lỗi hướng sang flow server.
Kết quả legacy không xác minh checkpoint toàn graph hoặc ASIC signoff.

Test v1 không tương thích đã được bỏ. Các ca arithmetic còn hữu ích từ bộ cũ đã được chuyển sang interface mới: reduction N=1/3/32/37/512, số âm và extrema, saturation, signed/unsigned multiplication và RNE.

## Demo checkpoint

- [NanoFable toàn graph](../docs/demos/language.md): checkpoint thật và application gate cho llm_soc.
- [NanoFable assets](language_demo/README.md): setup, pinned files và dependencies.
- [Demo legacy](../docs/demos/legacy/README.md): MNIST và NanoFable hybrid đã lưu.

Dependency và build cache ở local, tách khỏi source. Xem
[trạng thái kiểm chứng](../docs/verification/optimization_status.md) trước khi
chạy pretrained export/reference/application.
