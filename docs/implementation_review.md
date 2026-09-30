# Rà soát và tích hợp NPU ASIC v2

Ngày 29/09/2026. Đã tích hợp và sửa RTL/LUT trong `Verilog Source code`, rồi chạy regression trên source chính. Ngày 30/09/2026 đã xóa các bản source trùng và snapshot v1; giữ báo cáo này để lưu các lỗi đã sửa và giới hạn triển khai.

## Kết luận

Bản v2 ban đầu đúng hướng 32 PE, INT8×ternary, ACC18, state S16, SRAM 256 bit, nhưng có lỗi chức năng nên không thể copy nguyên trạng. Bản đã sửa vượt qua regression số học/giao tiếp đã liệt kê dưới đây. Chưa xác nhận đây là ASIC đã tối ưu diện tích hoặc sẵn sàng tape-out.

## Những lỗi đã sửa

| Khối | Vấn đề trong bản nhận được | Cách sửa |
|---|---|---|
| Ternary core | `6'd64` bị truncate về 0; các chunk trong cùng word chọn lại nhóm weight đầu tiên | Dùng `{chunk[1:0],6'b0}`; cache một word weight cho tối đa bốn chunk; kiểm tra K/tail và biên S8 |
| Ternary descriptor | Không kiểm tra length, format, vùng memory, K=0/K>512 và overlap | Từ chối cấu hình sai trước khi đọc/ghi; mã weight `10` báo lỗi; thêm no_bias flag |
| Sigmoid | Grid 32 bit tràn với input lớn ở scale nhỏ; RNE phần delta bỏ qua parity của mẫu đầu | Grid 64 bit, giữ 24 bit phần lẻ; RNE trên toàn giá trị nội suy |
| Sigmoid LUT | Data 257 mẫu đúng, nhưng chỉ `$readmemh` theo working directory; file thiếu có thể để ROM không xác định | ROM mặc định được generate vào `.svh`; file override kiểm tra tồn tại, số mẫu và giá trị |
| NORM + QUANT | Không kiểm tra descriptor/overlap/bounds; tự clamp K; epsilon cộng vào U64 có thể wrap | Kiểm tra đầu vào, intermediate 65 bit để phát hiện overflow, báo lỗi và dừng |
| Scale giữa NORM và BitLinear | NORM tạo q có scale động nhưng TMATMUL vẫn dùng hệ số tĩnh | Xuất D, lưu theo descriptor, tạo M/r postscale bằng scalar divider; vô hiệu metadata khi q bị ghi đè |
| Vector unit | Thiếu latch control, không xử lý đúng shift trái và output scale; tính cả tail không hữu ích | Latch descriptor, hỗ trợ rescale theo tensor, mask tail và zero padding, kiểm tra gate U16 |
| MLGRU state | Dùng hai MUL rồi ADD sẽ làm tròn hai tích riêng, khác công thức trong doc | Thêm REC opcode B: hai tích cộng ở S33, chỉ RNE một lần trước S16 |
| ReLU | MLP demo cần ReLU nhưng scheduler chưa có | Thêm opcode C cho ReLU với rescale và saturation |
| Host / scheduler | Decode window rộng hơn dung lượng thật gây alias; báo ready cả khi ghi bị bỏ; lỗi opcode vẫn chạy tiếp | Decode đúng range/alignment, chỉ acknowledge truy cập được chấp nhận, dừng khi error và ngăn PC wrap |
| Reduction | Cộng tuần tự bằng vòng lặp tạo chuỗi cộng dài | Chuyển sang reduction tree cân bằng |
| Wrapper | Wrapper v1 gọi port carry_out không còn có trong top v2 | Cập nhật host ports và LED ready/overflow/error |

## Kiểm chứng đã chạy

Tool: ModelSim Intel FPGA Edition 2020.1. Reference sử dụng Python integer, `isqrt`, phép chia có dư và RNE; dữ liệu LUT được đối chiếu bằng Decimal exp ở precision 70 chữ số.

| Kiểm tra | Kết quả |
|---|---|
| Compile toàn bộ `.sv`/`.v` trong project chính, package trước module | **0 error, 0 warning** |
| Host regression | **146 ca pass**, 17.749 host commands |
| NORM | K=1,2,3,7,8,15,16,17,28,31,32,33,63,64,65,96,127,128,129,160,255,256,257,511,512; zero vector, full-scale, epsilon, delta, buffer guards |
| TMATMUL | K/tail, weight khác nhau theo chunk, ±128, S16/S32 output, saturation, bias/no-bias, reserved code, descriptor guards |
| Chuỗi NORM→TMATMUL | Scale động, cache scale theo q và trường hợp metadata không hợp lệ |
| Vector | ADD/SUB/MUL, shift trái/phải, gate unsigned, tail, REC single rounding, ReLU |
| Sigmoid ROM mặc định | **393.216 ca pass**: toàn bộ S16 tại F_t=0,4,8,12,15,24 |
| Sigmoid đọc file ngoài | **393.216 ca pass** cùng tập input |
| File LUT thiếu / sai mẫu 128 | **2 ca negative test pass**: fatal đúng thông báo dự kiến |
| Scalar | 105 phép chia U64, 105 căn U64, 5 biên RNE, 6 trường hợp biên hệ số pass |

Log negative test cố ý có Fatal/Error: đó là kết quả mong đợi khi LUT không hợp lệ. Các test chạy bình thường không có warning/error. File `tests/results.json` ghi SHA256 của nguồn đã kiểm tra, tránh nhầm log của bản v2 chưa sửa với bản project chính.

Chạy lại bằng `./tests/run.ps1 -Block All`. Các suite v1 không còn phù hợp đã được loại bỏ. Các test còn giá trị được chuyển vào `tests/tb_all.sv`, dùng interface source chính.

## Những gì chưa được xác nhận

Cập nhật sau đợt refactor: MUL và REC đã dùng chung hai phép nhân 16×16 trong vector unit; LUT synthesis dùng bảng hằng, memory có wrapper chung và đường ghi masked không asynchronous reset. Xem README project chính để biết code hiện hành. Các giới hạn ở đây về sharing **toàn chip**, macro binding và PPA vẫn áp dụng.

- **Resource sharing:** RTL chức năng vẫn chứa các phép nhân rộng ở nhiều engine. Chưa triển khai dùng chung đúng hai multiplier 16×16 cho toàn chip. Hai lane xử lý trong control không phải bằng chứng số multiplier trong netlist.
- **SRAM macro:** memory hiện là behavioral array có giao tiếp host, chưa bind macro một cổng của PDK. Dung lượng 32+8 KiB là dung lượng logic.
- **ASIC:** chưa chạy synthesis, STA, area/power, DFT hoặc physical design.
- **Model:** chưa export/chạy một checkpoint hoàn chỉnh. Regression dùng tensor tổng hợp; không chứng minh chất lượng hội thoại. Tokenization/argmax nằm trên host ở bản này.
- **Scheduling:** epsilon_raw32 là thanh ghi chung; các NORM có scale/epsilon khác nhau cần host lập lịch cập nhật. Chưa có per-descriptor epsilon.

Vì vậy project chính hiện là **bản RTL chức năng đã kiểm tra**, còn mục tiêu diện tích của ASIC cần bước resource sharing và macro binding tiếp theo. Xem `Verilog Source code/README.md` để biết ISA, descriptor, host map và cách dùng LUT hiện hành.
