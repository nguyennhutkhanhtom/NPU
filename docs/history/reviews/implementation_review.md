# Rà soát và tích hợp source NPU hiện hành

<!-- reading-navigation:start -->
[Documentation](../../README.md) → [Archive](../../archive/README.md) → This page

| Reading guide | Document |
|---|---|
| Read first | [Historical context](../../archive/README.md) |
| Continue / related lookup | [Current evidence](../../verification/optimization_status.md) |
<!-- reading-navigation:end -->

> **Category: HISTORICAL SNAPSHOT — see dated checkpoints below.** This snapshot must not determine current architecture, live status or active tasks.

Phạm vi dưới đây là core legacy `matmulfree`. Top mới `llm_soc` có graph
đầy đủ và adapter SRAM khác; xem [thiết kế hiện tại](<../../design/full_rtl_language.md>)
và [gates thực tế](<../../verification/timing/README.md>).

Tài liệu cập nhật ngày 01/10/2026. RTL/LUT được tích hợp từ ngày 29/09, sửa tiếp ngày 30/09 và tối ưu ngày 01/10. Sau đó đã bỏ nhánh `SYNTHESIS`/`QUARTUS_SYNTHESIS`, thuộc tính memory riêng của Intel và LUT file override để core dùng một implementation. Quartus dùng để demo synthesis và timing FPGA; mục tiêu thiết kế vẫn là ASIC. Các bản source trùng và snapshot v1 đã loại bỏ; xem [báo cáo cải tiến và kiểm chứng](<design_review.md>) và [critical path/Fmax](<../../verification/timing/README.md>).

## Kết luận

Bản v2 ban đầu đúng hướng 32 PE, INT8×ternary, ACC18, state S16, SRAM 256 bit, nhưng có lỗi chức năng nên không thể copy nguyên trạng. Các lỗi và kết quả kiểm tra lịch sử được liệt kê dưới đây; trạng thái bản RTL thống nhất nằm trong [báo cáo rà soát](<design_review.md>). Chưa xác nhận đây là ASIC đã tối ưu diện tích hoặc sẵn sàng tape-out.

## Những lỗi đã sửa

| Khối | Vấn đề trong bản nhận được | Cách sửa |
|---|---|---|
| Ternary core | `6'd64` bị truncate về 0; các chunk trong cùng word chọn lại nhóm weight đầu tiên | Dùng `{chunk[1:0],6'b0}`; cache một word weight cho tối đa bốn chunk; kiểm tra K/tail và biên S8 |
| Ternary descriptor | Không kiểm tra length, format, vùng memory, K=0/K>512 và overlap | Từ chối cấu hình sai trước khi đọc/ghi; mã weight `10` báo lỗi; thêm no_bias flag |
| Sigmoid | Grid 32 bit tràn với input lớn ở scale nhỏ; RNE phần delta bỏ qua parity của mẫu đầu | Grid S45 đã chứng minh đủ cho F_t=0..24, giữ 24 bit phần lẻ; RNE trên toàn giá trị nội suy |
| Sigmoid LUT | Data 257 mẫu đúng, nhưng chỉ `$readmemh` theo working directory; file thiếu có thể để ROM không xác định | ROM hằng được generate vào `.svh`, dùng cho mọi build; file `.mem` chỉ để generate/đối chiếu, không có file override trong RTL |
| NORM + QUANT | Không kiểm tra descriptor/overlap/bounds; tự clamp K; epsilon cộng vào U64 có thể wrap | Kiểm tra đầu vào, intermediate 65 bit để phát hiện overflow, báo lỗi và dừng |
| Scale giữa NORM và BitLinear | NORM tạo q có scale động nhưng TMATMUL vẫn dùng hệ số tĩnh | Xuất D, lưu theo descriptor, tạo M/r postscale bằng scalar divider; vô hiệu metadata khi q bị ghi đè |
| Vector unit | Thiếu latch control, không xử lý đúng shift trái và output scale; tính cả tail không hữu ích | Latch descriptor, hỗ trợ rescale theo tensor, mask tail và zero padding, kiểm tra gate U16 |
| MLGRU state | Dùng hai MUL rồi ADD sẽ làm tròn hai tích riêng, khác công thức trong doc | Thêm REC opcode B: hai tích cộng ở S33, chỉ RNE một lần trước S16 |
| ReLU | MLP demo cần ReLU nhưng scheduler chưa có | Thêm opcode C cho ReLU với rescale và saturation |
| Host / scheduler | Decode window rộng hơn dung lượng thật gây alias; báo ready cả khi ghi bị bỏ; lỗi opcode vẫn chạy tiếp | Decode đúng range/alignment, chỉ acknowledge truy cập được chấp nhận, dừng khi error và ngăn PC wrap |
| Reduction | Cộng tuần tự bằng vòng lặp tạo chuỗi cộng dài | Chuyển sang reduction tree cân bằng |
| Wrapper | Wrapper v1 gọi port carry_out không còn có trong top v2 | Cập nhật host ports và LED ready/overflow/error |
| SRAM inference | Đọc host bất đồng bộ và ghi slice khiến SRAM lớn thành FF | Dùng 8 bank 32 bit, whole-word write với enable từng lane, shared synchronous read trong mọi build; không async reset RAM/read data, không dùng primitive/thuộc tính riêng của Intel |
| Host SRAM valid | Read sau đổi địa chỉ, write hoặc idle có thể nhận response cũ | Backend so khớp request/response row + lane sau hai cạnh lên; frontend top thêm request/response registers, host SRAM read bốn cạnh |
| Descriptor inference | Partial write vào packed struct với dynamic index thành latch | Generate index hằng, 8 workspace word và 8×3 matrix word FF 32 bit; reset đủ 1.024 FF, không latch |
| Package RNE | Biến tạm shift=0 có thể tạo pin function không driver | Gán đầy đủ mọi biến trên mọi path; giữ kết quả RNE |
| Độ rộng và PC | Cast/increment/shift ngầm tạo warnings; clear gộp trong reset PC | Sized casts và unsigned shift rõ ràng; bỏ biến không dùng; clear synchronous tách khỏi rst_n asynchronous |
| NORM dispatch | Descriptor mới bị từ chối có thể báo lại overflow của NORM trước | Mask overflow của core khi request bị từ chối; test chuỗi overflow→invalid không reset |
| Alias của q | TM scale tĩnh kiểm tra ID mà chưa kiểm tra extent của các descriptor alias | So overlap với mọi q metadata hợp lệ; từ chối alias cùng vùng và partial overlap |
| Metadata scale | Payload không hợp lệ vẫn reset asynchronous cùng valid | Chỉ reset q_valid; 336 bit D/base/length ghi đầy đủ khi NORM thành công, mọi consumer được gate bởi valid |

## Kiểm chứng implementation thống nhất

Ngày 01/10/2026, `./tests/run.ps1 -Block All` pass **10 mục kiểm tra** lúc **14:31:18**: xác minh ROM và chín testbench RTL; compile toàn source **0 error / 0 warning**. Source/test hashes khớp snapshot được kiểm tra. Suite không dùng macro chọn nhánh.

168 ca host / 23.827 commands; scalar 37.189 RNE, 106 divider, 4.301 sqrt, 900 exact compose (max 99 clock); 5 divider profiles / 2.320 checks; 12.720 postscale; sigmoid 1.638.400 input ở đủ 25 F_t; instruction memory 1.027; SRAM 47; arithmetic 3.242 addsub, 4.452 mul và 5 accumulator profiles. Host frontend thêm 30 protocol reads, 11 cancellations và 4 running-blocked regions. Bao gồm reset/busy-start/input capture, no-reset overflow→reject và alias metadata.

Testbench rowwise riêng kiểm tra thêm 1.800 ca/13.260 phần tử với reference S128, 42.843 thay đổi input khi busy và reset tại sáu pha; xác nhận register boundary mới giữ phép tính, tail và cờ.

Demo Analysis & Synthesis trước tối ưu timing thành công lúc **11:24:04**, **0 error / 0 warning**, 6.497 FF, 11.798 ALUT, 334.336 bit block RAM và 7 DSP. Đây là số liệu synthesis của snapshot lịch sử; [báo cáo timing](<../../verification/timing/README.md>) ghi kết quả và cấu trúc datapath sau khi xét critical path.

## Kiểm chứng lịch sử trước khi bỏ macro

Tool: ModelSim Intel FPGA Edition 2020.1. Reference sử dụng Python integer, `isqrt`, phép chia có dư và RNE; dữ liệu LUT được đối chiếu bằng Decimal exp ở precision 70 chữ số.

| Kiểm tra | Kết quả |
|---|---|
| Compile toàn bộ `.sv`/`.v` trong project chính, package trước module | **0 error, 0 warning** |
| Host regression | **162 ca pass**, 23.396 host commands |
| NORM | K=1,2,3,7,8,15,16,17,28,31,32,33,63,64,65,96,127,128,129,160,255,256,257,511,512; zero vector, full-scale, epsilon, delta, buffer guards |
| TMATMUL | K/tail, weight khác nhau theo chunk, ±128, S16/S32 output, saturation, bias/no-bias, reserved code, descriptor guards |
| Chuỗi NORM→TMATMUL | Scale động, cache scale theo q và trường hợp metadata không hợp lệ |
| Vector | ADD/SUB/MUL, shift trái/phải, gate unsigned, tail, REC single rounding, ReLU |
| Sigmoid ROM mặc định | **393.216 ca pass**: toàn bộ S16 tại F_t=0,4,8,12,15,24 |
| Sigmoid đọc file ngoài | **393.216 ca pass** cùng tập input |
| File LUT thiếu / sai mẫu 128 | **2 ca negative test pass**: fatal đúng thông báo dự kiến |
| Scalar | 105 phép chia U64, 105 căn U64, 37.189 kiểm tra RNE, 6 trường hợp biên hệ số pass |
| Arithmetic helpers | 3.242 ca addsub, 4.452 ca mul, 5 accumulator profiles pass ở mỗi chế độ |
| SRAM synchronous | 47 kiểm tra pass, gồm lane write và synchronous host read/valid |
| Cấu trúc synthesis riêng | Descriptor 1.024 FF, không latch; SRAM workspace 65.536 bit block RAM; instruction RAM 6.656 bit / 22 FF |
| Instruction memory | 1.027 kiểm tra mỗi mode, mọi địa chỉ/client, overwrite/re-read, restart/reset |
| Toàn project Ctrl+K | 0 error, 0 warning; 6.712 FF, 334.336 bit block RAM, 7 DSP |

Đây là kết quả snapshot trước khi bỏ macro: suite cũ pass 19 lượt lúc 01:17:21 ngày 01/10/2026 trên ba cấu hình thường/`SYNTHESIS`/`SYNTHESIS + QUARTUS_SYNTHESIS`; kiểm tra cấu trúc riêng pass lúc 01:23:09; Analysis & Synthesis toàn project pass lúc 01:17:35. Các test file override/negative đã thuộc interface LUT cũ và không mô tả interface hiện hành. Regression hiện tại chạy một implementation và kiểm tra ROM hằng, read-valid/latency và tensor bit-exact; xem [kết quả của bản bỏ macro](<design_review.md>).

Trong suite lịch sử, log negative test cố ý có Fatal/Error khi LUT không hợp lệ. File [tests/results.json](<../../../tests/results.json>) ghi SHA256 của nguồn đã kiểm tra để phân biệt kết quả giữa các snapshot; kết quả mới thay thế kết quả suite cũ.

Chạy lại bằng `./tests/run.ps1 -Block All`. Các suite v1 không còn phù hợp đã được loại bỏ. Các test còn giá trị được chuyển vào `tests/tb_all.sv`, dùng interface source chính.

## Những gì chưa được xác nhận

Cập nhật sau đợt refactor: MUL và REC đã dùng chung hai phép nhân 16×16 trong vector unit; LUT luôn dùng bảng hằng, memory có wrapper synchronous chung và đường ghi masked không asynchronous reset. Xem README project chính để biết code hiện hành. Các giới hạn ở đây về sharing **toàn chip**, macro binding và PPA vẫn áp dụng.

- **Resource sharing:** RTL chức năng vẫn chứa các phép nhân rộng ở nhiều engine. Chưa triển khai dùng chung đúng hai multiplier 16×16 cho toàn chip. Hai lane xử lý trong control không phải bằng chứng số multiplier trong netlist.
- **SRAM macro:** parameter 262.144 bit + workspace 65.536 bit được mô tả bằng array synchronous và adapter dùng chung cho mọi build; chưa bind macro SRAM của PDK. Suy luận block RAM trong demo Quartus và dung lượng 32+8 KiB không phải số liệu diện tích ASIC.
- **ASIC:** chưa chạy synthesis, STA, area/power, DFT hoặc physical design.
- **Model:** đã export/chạy [Binary-MNIST160](<../../demos/legacy/mnist.md>) với 10 ảnh mẫu, đối chiếu 40 lượt tầng và hai lần chạy graph liên tục. [NanoFable](<../../demos/language.md>) chạy generation trên CPU (3 prompt × 32 token, deterministic repeat) và 168 lượt linear ternary thực trên RTL, 33.792 output S32 bit-exact. Affine RMSNorm, RoPE, attention, gating và output head vẫn ở CPU; chưa chạy toàn model trên NPU hoặc đánh giá toàn bộ MNIST/chất lượng hội thoại. Tokenization/argmax nằm trên host ở bản này.
- **Scheduling:** epsilon_raw32 là thanh ghi chung; các NORM có scale/epsilon khác nhau cần host lập lịch cập nhật. Chưa có per-descriptor epsilon.

Project chính là **RTL chức năng dùng một implementation cho mô phỏng và synthesis**. Kiểm tra FPGA là bước demo khả năng tổng hợp; mục tiêu diện tích ASIC cần resource sharing và macro binding tiếp theo. Xem [README source](<../../design/legacy/interfaces.md>) để biết ISA, descriptor, host map và LUT hiện hành.

---

[Đọc tiếp: design review hiện hành](<design_review.md>) · [Lịch sử](<../README.md>) · [Về mục lục tài liệu](<../../README.md>)
