# Kiểm thử riêng IP sigmoid — Q4.12

**Kết luận: FAIL_DEFAULT_Q4_12.** Khối `sigmoid` với tham số mặc định `(inWidth=16, dataWidth=16)` và LUT hiện có **không đáp ứng đầu vào Q4.12 đầy đủ**. Không sửa RTL, LUT hoặc script sinh LUT. Không compile/test ALU, `rowwise_op` hoặc core.

## Phạm vi và chuẩn đối chiếu

- DUT: `Verilog Source code/sigmoid.sv` nguyên trạng; `sigContent.mif` sao chép nguyên byte từ cùng thư mục vào thư mục mô phỏng riêng. Hai bản LUT trong `Verilog Source code` và `data/sigmoid` có SHA-256 giống nhau.
- Q4.12 có 16 bit signed, 4 bit phần nguyên gồm dấu; miền [-8, 7.999755859375], LSB = 1/4096 = 0.000244140625.
- Golden độc lập dùng Python Decimal precision=50: `round_half_even(4096 / (1 + exp(-raw_signed/4096)))`. Không gọi/import script sinh LUT. Quy tắc làm tròn gần nhất khớp script hiện tại; không có kết luận ngầm rằng mọi LUT xấp xỉ phải có sai số 0 nếu yêu cầu cho phép sai số khác.
- Quét **65.536/65.536 mã đầu vào**, theo thứ tự signed tăng dần. Mỗi input giữ 1 ns cho logic tổ hợp ổn định; đây là functional simulation, không xác nhận timing sau synthesis.
- Thêm **4.112 lần đổi đầu vào**: 16 tình huống biên/đổi dấu/lặp giá trị và 4.096 mẫu xorshift seed cố định. Số kết quả khác lần quét đầu: **0**.
- Cấu hình chẩn đoán thứ hai: cùng RTL, override `inWidth=10`, output 16 bit, nhận `x[15:6]` **chỉ trong testbench**, đúng mô tả script sinh LUT. Có đủ 1.024 mã đầu vào Q4.6; mỗi mã được thử với cả 64 tổ hợp bit thấp của Q4.12. Đây không phải thay đổi thiết kế hay kiểm thử tích hợp.

## Kết quả

| Phép kiểm | Kết quả |
|---|---:|
| DUT mặc định 16 bit: trùng golden Q4.12 | 6/65536 |
| DUT mặc định: output xác định nhưng sai | 1018/65536 |
| DUT mặc định: output X/Z | 64512/65536 |
| DUT mặc định: mapping địa chỉ khác `raw XOR 0x8000` | 0 |
| LUT 1024 word so golden Q4.6 → Q4.12 | 0 lỗi |
| DUT 10 bit so golden tại đầu vào Q4.6 đã cắt | 65536/65536 đúng, 0 X/Z |
| DUT 10 bit: mapping địa chỉ / ngoài [0,1] / giảm đơn điệu | 0 / 0 / 0 lỗi |
| DUT 10 bit: symmetry `sigmoid(x)+sigmoid(-x)=4096` trên lưới Q4.6 có đối xứng | 0/512 lỗi |
| DUT 10 bit so golden của Q4.12 ban đầu | 32450/65536 trùng, 33086/65536 khác |
| DUT 10 bit: sai số tối đa so golden Q4.12 ban đầu | 16 LSB = 0.00390625 |
| DUT 10 bit: số input sai quá 1 LSB so golden Q4.12 ban đầu | 21065/65536 |

## Sai ở đâu

### F01 — Không tương thích độ rộng IP với số entry/scale LUT (FAIL)

- `Verilog Source code/sigmoid.sv:1` mặc định `inWidth=16`; dòng 6 tạo `2**16=65536` word; dòng 11 nạp `sigContent.mif`.
- Bảng đang có **1024 dòng**, được sinh cho **input 10-bit Q4.6**, bước 1/64. Xem `python/generate_sigmoid_lut.py:7` và các default ở dòng 44–47. Bảng đúng số học trong miền/scale riêng của nó.
- DUT 16 bit truy cập địa chỉ 0..65535 nhưng chỉ 0..1023 được nạp. **Địa chỉ 1024..65535 cho output X**, tương ứng input signed raw -31744..32767 (x từ -7.75 đến 7.999755859375). Đây là nguyên nhân 64512 input không có kết quả số; không gán X thành 0 và không tính X vào sai số số học.
- **Ngay cả 1024 địa chỉ đã nạp cũng lệch scale**: với DUT16, địa chỉ `a` phải biểu diễn `x=-8+a/4096`; LUT hiện biểu diễn `x=-8+a/64`. Trong vùng này có 1018 output sai và 6 output tình cờ bằng golden sau làm tròn.
- Sai số lớn nhất trong vùng output xác định: raw input `83fb`, x=-7.751220703125, actual=4095, expected=2, lệch **4093 LSB**. Không coi đây là sai số tối đa toàn miền vì phần còn lại là X.
- `sigmoid.sv:17–20` ánh xạ dấu/địa chỉ đúng trong cả hai cấu hình được kiểm tra; không tìm thấy lỗi riêng trong phép cộng/trừ offset này.

### F02 — Cấu hình 10 bit là xấp xỉ đầu vào, không bảo toàn 12 bit phần lẻ (giới hạn độ chính xác)

- Cấu hình 10 bit hoạt động đúng với input Q4.6 và LUT hiện tại: toàn bộ 1.024 mã đều cho giá trị Q4.12 đúng theo làm tròn gần nhất.
- Nếu bắt đầu từ Q4.12 rồi lấy `x[15:6]`, input bị lượng tử xuống lưới Q4.6 (floor, kể cả số âm). So với sigmoid của **input Q4.12 gốc**, sai số có thể **16 LSB**. Ví dụ raw `fa3f` (x=-0.359619140625): actual=1668, golden=1684.
- Q4.12 chỉ xác định cách mã hóa; nếu yêu cầu chính xác là đúng giá trị sau làm tròn hoặc ≤1 LSB trên toàn miền, cấu hình chẩn đoán này cũng không đạt. Nếu được phép LUT xấp xỉ với ngưỡng khác, phải đánh giá theo ngưỡng đó. Nó không làm thay đổi kết luận FAIL của cấu hình mặc định hiện tại do output X.

## Ví dụ từ mô phỏng thực

Giá trị đều là raw hex 16 bit, output chia 4096 để ra số thực. `xxxx` là unknown. Cột 10 bit là cấu hình chẩn đoán trong testbench.

| x thực Q4.12 | Input | Golden Q4.12 | DUT mặc định | Địa chỉ DUT | DUT 10 bit |
|---:|---|---|---|---|---|
| -8 | `8000` | `0001` | `0001` | `0000` | `0001` |
| -7.984375 | `8040` | `0001` | `0004` | `0040` | `0001` |
| -7.875 | `8200` | `0002` | `0800` | `0200` | `0002` |
| -7.75024414062 | `83ff` | `0002` | `0fff` | `03ff` | `0002` |
| -7.75 | `8400` | `0002` | `xxxx` | `0400` | `0002` |
| -1 | `f000` | `044e` | `xxxx` | `7000` | `044e` |
| -0.000244140625 | `ffff` | `0800` | `xxxx` | `7fff` | `07f0` |
| 0 | `0000` | `0800` | `xxxx` | `8000` | `0800` |
| 0.000244140625 | `0001` | `0800` | `xxxx` | `8001` | `0800` |
| 0.015380859375 | `003f` | `0810` | `xxxx` | `803f` | `0800` |
| 0.015625 | `0040` | `0810` | `xxxx` | `8040` | `0810` |
| 1 | `1000` | `0bb2` | `xxxx` | `9000` | `0bb2` |
| 7.99975585938 | `7fff` | `0fff` | `xxxx` | `ffff` | `0fff` |

## Tái lập và bằng chứng

- Chạy từ workspace: `& '.\review\sigmoid_20260918\run.ps1'`.
- Runner chỉ compile `sigmoid.sv` và `tb_sigmoid.sv`, dùng ModelSim Intel FPGA Starter 2020.1. Exit code 1 là audit chạy hoàn tất nhưng DUT mặc định FAIL; lỗi hạ tầng cũng được báo bằng exception riêng.
- `sim/compile.log`: compile; `sim/simulation.log`: transcript; `sim/observed.csv`: đủ 69.648 dòng dữ liệu, gồm input, output và địa chỉ của hai DUT.
- `verification.json`: số đo và SHA-256 trước/sau của mọi file trực tiếp trong thư mục RTL, cả hai LUT và generator; xác nhận **không thay đổi các file thiết kế**.
- `$readmemb("sigContent.mif",...)` dùng đường dẫn tương đối với working directory. Audit đã cung cấp đúng bản LUT hiện có bằng cách copy nguyên byte vào thư mục mô phỏng riêng, không dùng fixture zero, không sinh đè LUT và không sửa path của RTL.

Chưa tự sửa bất kỳ lỗi nào. Các file mới chỉ nằm trong `review/sigmoid_20260918` để kiểm thử và báo cáo.
