# Demo checkpoint BitNetMCU trên NPU

> **Category: LEGACY.**

[Project](<../../../README.md>) → [Tài liệu](<../../README.md>) → [Demo](<../README.md>) → **Binary-MNIST160**

Đã chạy model **Binary-MNIST width160_160_160** được đề xuất trong [danh sách model](<../candidates.md>), sử dụng weight đã huấn luyện công khai. Graph thực tế là **256→160→160→160→10**, ba ReLU, RMSNorm không affine trước mỗi linear layer; không có bias. RTL dùng bản portable sau tối ưu timing; [rà soát design](<../../history/reviews/design_review.md>) ghi các register boundary mới.

## Kết quả

Lượt demo ngày **01/10/2026 lúc 14:30:25** pass **22.492 commands / 12.402 so sánh host**, compile và mô phỏng **0 error / 0 warning**.

| Kiểm tra | Kết quả |
|---|---|
| Model PyTorch gốc trên CPU | 10/10 ảnh mẫu đúng nhãn |
| Reference số nguyên sau export | 10/10 đúng nhãn, cùng dự đoán với CPU |
| RTL chạy graph đã export | 10/10 đúng nhãn, không error/overflow |
| Dữ liệu trung gian | 40 lượt tầng: output, q, z, D, hệ số NORM/QUANT khớp bit-exact với reference số nguyên |
| Chương trình toàn graph | 12 instruction gồm HALT; chạy hai lần, lần thứ hai không reset/nạp lại |
| Chu kỳ xử lý toàn graph | 20.783 clock cho mỗi lần chạy toàn graph của ảnh số 0; chưa tính host load/readback |

![Ảnh mẫu, nhãn và dự đoán CPU/RTL](<../mnist.png>)

Đây là **10 ảnh 16×16 đã preprocess** từ header mẫu của upstream, không phải phép đo accuracy trên toàn MNIST. Bit-exact áp dụng giữa RTL và reference số nguyên; các activation không bắt buộc trùng bit với mô hình float32 gốc. Clock 10 ns trong testbench không xác nhận timing ASIC.

## Checkpoint và cách chuyển đổi

- [Checkpoint và mã hiện hành đã pin commit](https://github.com/cpldcpu/BitNetMCU/tree/0715bfc4ed9f2578496e17b4b0e13f2297e3cc0f/modeldata).
- [Graph/quantizer tại commit thêm checkpoint](https://github.com/cpldcpu/BitNetMCU/blob/1e06ef3b3c028aac516dc7ad7607cfe61af31320/BitNetMCU.py).
- [Header chứa dữ liệu mẫu](https://github.com/cpldcpu/BitNetMCU/blob/0715bfc4ed9f2578496e17b4b0e13f2297e3cc0f/BitNetMCU_MNIST_test_data.h).
- SHA-256 checkpoint: `cd1573f0bfd7f4b1bc734601d98c9df122a2a8fedf41066f4ba9bd17ac4af289`.

Exporter đọc metadata tensor bằng restricted pickle reader và load strict bốn tensor vào graph lịch sử. CPU chạy chính implementation PyTorch đó, với PyTorch **2.5.1+cpu** và một thread. Runtime/dependency được cài riêng trong `tests/model_demo/packages`, không sửa môi trường Python chung.

Weight dùng quantizer float32 `sign(w−mean(w))`; gain từng tầng `mean(abs(w))` được giữ trong M/r của descriptor động. Có một weight đúng tại mean nên mang mã zero. Mã −1/0/+1 được đóng gói `11/00/01`, không dùng format đóng gói gốc của BitNetMCU. Hidden state dùng **S16/F9**, logits **S32/F16**; input S8 được mở rộng dấu lên S16. NORM dùng epsilon=0 và delta=1 cho demo này.

Host chỉ nạp weight, input, descriptor và instruction; không ghi các giá trị q/z/hidden từ reference. Mười ảnh chạy với HALT sau mỗi tầng để quan sát đủ 40 output và metadata. Một chương trình liên tục chạy cả graph trên ảnh số 0 hai lần để kiểm tra scheduler/restart và kết quả cuối mà không có can thiệp giữa các tầng.

## Memory

| Vùng | Dùng / dung lượng |
|---|---|
| Weight | 980 word ×256 bit = **31.360/32.768 byte**, còn 1.408 byte |
| Workspace payload đã cấp phát | **2.496 byte** |
| Địa chỉ workspace cao nhất | Byte 5.119; vùng trải đến **5.120/8.192 byte** vì base cố định |
| Instruction | **12/512 word**, trong đó 11 lệnh engine và một HALT |

Parameter image đầy đủ gồm 1.024 word, điền zero vào phần dư; upload dùng 8.192 host write 32 bit. Số chu kỳ inference ở trên tách khỏi nạp/đọc qua host. Bias không chiếm SRAM vì checkpoint không có bias; descriptor và scale runtime nằm trong các thanh ghi core.

## Bằng chứng lịch sử

[README snapshot](<../../../tests/model_demo/README.md>) ghi việc loại bỏ runner/exporter/testbench
legacy. [results.json](<../../../tests/model_demo/results.json>) giữ checkpoint, tool version,
source/asset hashes, predictions, checks và cycles. Các image
[parameter.mem](<../../../tests/model_demo/parameter.mem>), [program.mem](<../../../tests/model_demo/program.mem>),
[program_layout.json](<../../../tests/model_demo/program_layout.json>) và
[cpu_reference.json](<../../../tests/model_demo/cpu_reference.json>) giữ layout/reference để tra cứu.
Đây là demo legacy, không phải gate hay application của full `llm_soc`.

---

[Các demo khác](<../README.md>) · [Kiến trúc và memory](<../../design/legacy/architecture.md>) · [Về mục lục tài liệu](<../../README.md>)
