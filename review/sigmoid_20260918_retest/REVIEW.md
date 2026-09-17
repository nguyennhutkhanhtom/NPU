# Kiểm thử lại sigmoid sau chỉnh sửa — 18/09/2026

**Kết quả:** `PASS_LOOKUP_AND_CLOCK_WITH_Q4_12_APPROXIMATION`. So với chuẩn sigmoid Q4.12 làm tròn gần nhất: `FAIL`; nếu yêu cầu sai số ≤1 LSB: `FAIL`.

IP mới nhận 16-bit Q4.12, dùng 10 bit cao tra ROM 1024 phần tử và chốt địa chỉ tại cạnh lên `clk`. Lỗi thiếu entry/lệch ánh xạ của lần trước đã hết trong bản này. Giá trị output mã hóa Q4.12 đúng, nhưng sigmoid được tính tại đầu vào đã lượng tử xuống Q4.6, nên chưa đạt độ chính xác đầy đủ theo đầu vào Q4.12 gốc.

## Cách kiểm thử

- ModelSim Intel FPGA Starter 2020.1, chỉ compile RTL `Verilog Source code/sigmoid.sv` và testbench mới có `clk`. Không dùng testbench tổ hợp cũ; không compile/test ALU, rowwise hoặc core.
- Quét đủ **65.536 đầu vào** signed Q4.12 [-8, 7.999755859375], thêm **4.112 mẫu** đổi dấu, biên, lặp giá trị và ngẫu nhiên có seed cố định.
- Golden độc lập: Decimal precision=50, `round_half_even(4096 / (1 + exp(-raw_signed/4096)))`. Không gọi generator. Oracle thứ hai lấy input `floor(raw_signed/64)*64` để phân biệt lỗi lookup với sai số cắt bit.
- Đưa input ổn định 2 ns trước cạnh lên, đọc output 1 ns sau cạnh lên để tránh race với NBA. Chủ động thay đổi input khi clock thấp, khi clock cao và kiểm tra cạnh xuống. Đây là functional RTL simulation, không xác nhận timing sau synthesis.
- Copy nguyên byte LUT hiện tại vào thư mục mô phỏng riêng, kiểm tra SHA-256; không sinh lại hoặc sửa LUT.

## Kết quả đo

| Phép kiểm | Kết quả |
|---|---:|
| Output X/Z sau cạnh lên trên toàn miền | 0/65536 |
| Địa chỉ sai so với `floor(raw_signed/64)+512` | 0/65536 |
| Sai lookup so với sigmoid tại input đã cắt xuống Q4.6 | 0/65536 |
| LUT so với golden Q4.6 → Q4.12 | 0/1024 sai |
| Output nằm ngoài [0,1] | 0/65536 |
| Vi phạm đơn điệu trên miền signed tăng dần | 0 |
| Sai giữ giá trị giữa cạnh lên / tại cạnh xuống | 0/208944 |
| Mẫu bổ sung: X / sai lookup / khác lần quét trước | 0 / 0 / 0 trên 4112 mẫu |
| Trùng sigmoid chính xác của input Q4.12 sau làm tròn | 32450/65536 |
| Khác chuẩn Q4.12 sau làm tròn | 33086/65536 |
| Sai quá 1 LSB so chuẩn Q4.12 | 21065/65536 |
| Sai số tuyệt đối tối đa so chuẩn đã làm tròn | 16 LSB = 0.00390625 |
| Khoảng sai số có dấu actual − golden | [-16, 0] LSB |

## Vị trí còn gây sai lệch

**`Verilog Source code/sigmoid.sv:16`: `assign x_lut = x[15:6];`** bỏ 6 bit phần lẻ thấp. Do đó 64 mã Q4.12 liên tiếp cùng dùng một kết quả. LUT lấy mẫu với bước 1/64 trong khi input Q4.12 có bước 1/4096. Phép cắt này tương đương floor với số âm, không phải round-to-nearest.

Ví dụ input `0xFFFF` = −0.000244140625: sau cắt bit thành −0.015625, output `0x07F0` = 0.49609375, trong khi sigmoid của input gốc làm tròn Q4.12 phải là `0x0800` = 0.5. Sai **−16 LSB**.

Đây là giới hạn độ chính xác của LUT 10-bit theo cách lấy mẫu hiện tại. Q4.12 tự nó là định dạng mã hóa, không xác định ngưỡng sai số cho xấp xỉ. Nếu yêu cầu chỉ là input/output Q4.12 với LUT xấp xỉ cho phép sai số nêu trên thì lookup và clock đã đạt. Nếu yêu cầu kết quả làm tròn chính xác hoặc sai số ≤1 LSB trên toàn miền thì **chưa đạt**. Không tự chọn ngưỡng 16 LSB làm tiêu chí pass.

## Hành vi clock và khởi động

- `sigmoid.sv:18–23` chốt địa chỉ tại cạnh lên. Output phản ánh input được lấy mẫu ở cạnh đó sau khi register cập nhật và phép đọc ROM ổn định; không cập nhật ngay khi chỉ thay đổi input. Test đủ mọi input liên tiếp theo từng cạnh lên để kiểm tra không lệch mẫu.
- Trước cạnh lên đầu tiên, đo được `out=xxxx`, `y=xxx` vì thanh ghi `y` không có reset/initial. Sau cạnh lên có input xác định, output hợp lệ. Không kết luận đây là lỗi nếu đặc tả cho phép bỏ qua output lúc khởi động; chỉ ghi nhận giới hạn giao tiếp của IP.

## Ví dụ mô phỏng

Golden là sigmoid của input Q4.12 gốc, làm tròn gần nhất; actual được đọc sau cạnh lên.

| x | Input | Actual | Golden | Lệch LSB |
|---:|---|---|---|---:|
| -8 | `0x8000` | `0x0001` | `0x0001` | 0 |
| -7.875 | `0x8200` | `0x0002` | `0x0002` | 0 |
| -7.75 | `0x8400` | `0x0002` | `0x0002` | 0 |
| -1 | `0xf000` | `0x044e` | `0x044e` | 0 |
| -0.359619140625 | `0xfa3f` | `0x0684` | `0x0694` | -16 |
| -0.000244140625 | `0xffff` | `0x07f0` | `0x0800` | -16 |
| 0 | `0x0000` | `0x0800` | `0x0800` | 0 |
| 0.000244140625 | `0x0001` | `0x0800` | `0x0800` | 0 |
| 0.015380859375 | `0x003f` | `0x0800` | `0x0810` | -16 |
| 0.015625 | `0x0040` | `0x0810` | `0x0810` | 0 |
| 1 | `0x1000` | `0x0bb2` | `0x0bb2` | 0 |
| 7.99975585938 | `0x7fff` | `0x0fff` | `0x0fff` | 0 |

## Bằng chứng và tái lập

- Chạy: `& '.\review\sigmoid_20260918_retest\run.ps1'`. Exit code 1 biểu thị đã hoàn tất kiểm thử nhưng không trùng chuẩn Q4.12 chính xác; 2 là lỗi chạy audit; 3 là lỗi chức năng lookup/clock.
- `sim/compile.log`, `sim/simulation.log`, `sim/observed.csv`: log mới và 69.648 mẫu thực tế. Transcript có marker hoàn tất và số kiểm tra giữ output.
- `verification.json`: kết quả máy đọc và hash trước/sau của các file thiết kế, LUT, generator.
- Báo cáo lần trước được giữ nguyên tại `review/sigmoid_20260918/REVIEW.md`.

**Không sửa RTL, LUT, generator hoặc các file thiết kế khác.** Hash trước/sau trong lần kiểm thử này giống nhau.
