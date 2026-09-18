# NORM 32 × Q4.12

RTL hiện tại dùng `Verilog Source code/norm.sv` và được tích hợp vào `matmulfree.sv` qua `norm_dispatch.sv`. Mỗi thanh ghi của core chứa 16 word; mỗi word gồm 32 phần tử và **có RMS riêng**, đúng flow 32 đầu vào → 32 đầu ra. Không tính chung một RMS cho 512 phần tử.

## Quy tắc số học

Với `x_raw` là số nguyên có dấu 16 bit:

```text
q_i       = floor(x_raw_i / 64)           // lấy x[15:6], signed Q4.6
square_i  = q_i * q_i                    // LUT 1024 × 19 bit, frac = 12
S         = sum(square_i), i = 0..31     // 24 bit, diễn giải mean với frac = 17
rms_raw   = floor(sqrt(S * 128))         // unsigned 16 bit, frac = 12
y_raw_i   = saturate_int16(trunc_zero(x_raw_i * 4096 / rms_raw))
```

Nếu `rms_raw == 0`, trả về toàn zero. Không thêm epsilon hoặc gamma.

| Nút reduction tree | Số bit | Số bit phần lẻ khi diễn giải là trung bình |
|---|---:|---:|
| Square LUT | 19 | 12 |
| Trung bình 2 phần tử | 20 | 13 |
| Trung bình 4 phần tử | 21 | 14 |
| Trung bình 8 phần tử | 22 | 15 |
| Trung bình 16 phần tử | 23 | 16 |
| Trung bình 32 phần tử | 24 | 17 |

Cây chỉ cộng có mở rộng bit, không dịch phải làm mất LSB. `sqrt_radicand = S << 7` đổi từ mean có 17 bit lẻ sang bình phương RMS có 24 bit lẻ. RMS phải là unsigned: vector toàn `16'h8000` có RMS bằng `16'h8000`, tức **+8.0**. Phép chia dùng mẫu số mở rộng zero trước khi diễn giải có dấu.

Bước Q4.12 → Q4.6 có mất 6 bit thấp theo yêu cầu. Vì lấy bit trực tiếp, số âm làm tròn xuống: raw `-1` thành `-1` ở Q4.6, còn raw `+63` thành zero. Do đó vector toàn raw `1..63` cũng trả zero; đây là hệ quả của lượng tử hóa, không phải lỗi sqrt. Vector gốc vẫn được giữ đủ 16 bit để làm tử số.

Script `python/generate_norm_lut.py` và LUT có sẵn đã đúng. Kiểm tra độc lập xác nhận đủ 1.024 dòng 19 bit, giá trị `(address - 512)^2`. Không cần sửa thuật toán sinh LUT. File có đuôi `.mif` nhưng nội dung là binary text cho `$readmemb`, không phải cú pháp MIF của vendor.

## Giao tiếp và tích hợp

`norm` nhận `start` khi `busy=0`. Tại cạnh nhận lệnh, module lưu vector gốc và địa chỉ của 32 ROM. Cạnh kế tiếp lưu RMS; cạnh tiếp nữa cập nhật `out`, `overflow` và phát `done` một chu kỳ. Lệnh khi busy bị bỏ qua. `out` giữ ổn định đến kết quả mới; reset hủy phép tính đang chạy. `overflow` là OR các lane bị bão hòa, có hiệu lực cùng `done`.

Lệnh core vẫn là opcode `0111`: nguồn `instruction[2:0]`, đích `instruction[8:6]`. `norm_dispatch` giữ PC, đưa NOP vào pipeline khi các thao tác cũ đã lấy đủ word nguồn, và chờ cả pipeline lẫn các giao dịch bộ nhớ/thanh ghi kết thúc. Sau đó module mượn cổng đọc 0 và cổng ghi thanh ghi để xử lý lần lượt word 0..15. Lane 0 nằm ở `[15:0]`. Chỉ ghi khi kết quả đã sẵn sàng; PC tiến một lần sau word cuối. Hỗ trợ nguồn = đích và các lệnh NORM liên tiếp.

Reset hủy giao dịch; những word đã ghi trước reset không được hoàn tác. `instr_debug`, `pc_debug`, `overflow_out` và `carry_out=0` phản ánh NORM khi đang thực thi và tại xung nội bộ `norm_done`.

Đường dẫn mặc định là `data/normContent.mif`, tương đối với thư mục chạy simulator. Đổi bằng `norm.LUT_FILE`, `norm_dispatch.LUT_FILE` hoặc `matmulfree.NORM_LUT_FILE`. Thiếu file sẽ báo fatal trong mô phỏng. Khi chạy từ thư mục khác, cung cấp đường dẫn đúng hoặc copy asset; các runner bên dưới đã thực hiện việc này.

## Những lỗi đã sửa

- `rowwise_op` tham chiếu `norm_out` chưa khai báo, khiến RTL không compile. NORM nay đi qua controller nhiều chu kỳ; ALU tổ hợp không giả lập kết quả tức thời.
- NORM nạp tên `normContent.mif` ở thư mục chạy trong khi asset nằm trong `data/`. Đã thêm tham số đường dẫn và kiểm tra file.
- Kết nối ADD/SUB bị đảo tại `rowwise_op`; đồng thời sửa chọn cờ carry/overflow theo opcode và độ rộng cờ MUL. Đây là lỗi được phát hiện khi kiểm tra producer/consumer `ADD → NORM`.
- Hazard giải phóng lệnh đọc ở word 12, làm mất ba word cuối khi chuyển sang NORM hoặc khi store kết quả. Nay chờ tín hiệu word cuối thực sự từ register file.
- Store bỏ word cuối do loại `fifo_full` khỏi điều kiện ghi. Nay ghi cả cạnh cuối trước khi FSM về idle.
- HALT dùng các cờ endpoint đã mất hiệu lực sau khi pointer reset, gây treo sau store. Nay chờ trạng thái giao dịch thật; `ready` cũng yêu cầu bộ nhớ/thanh ghi đã rảnh.

## Chạy kiểm tra

Từ thư mục gốc dự án:

```powershell
./norm/run.ps1
./tmatmul/run.ps1
```

Có thể truyền `-SimBin` và `-Python` để đổi đường dẫn công cụ. Runner NORM sinh fixture bằng mô hình Python `math.isqrt`, so sánh đúng từng bit và ghi kết quả/hashes vào `norm/verification.json`. Các log nằm trong `norm/sim/`.

- ROM: toàn bộ 65.536 raw input Q4.12, đủ 1.024 địa chỉ LUT, kiểm tra giữ dữ liệu khi `en=0`.
- NORM: 3.797 vector / 121.504 lane, kiểm tra cả tổng không mất LSB, RMS, đầu ra và cờ bão hòa; gồm zero, MIN/MAX, số nhỏ, impulse ở mọi lane, các bin lượng tử hóa và random có seed.
- Handshake: thay đổi input sau start, start khi busy, giao dịch liên tiếp, reset ở cả hai pha tính toán và reset giữa một bank đang ghi.
- Core thật: năm lệnh NORM / 80 word ghi, bank cao, in-place, lệnh liên tiếp, ADD phụ thuộc trước/sau NORM; kiểm tra cả 128 word thanh ghi tại từng lần hoàn tất.
- Bộ nhớ: `LDV → NORM → STV → LDV → NORM`, kiểm tra đủ word đầu/cuối.
- TMATMUL: hai frame chạy trước/sau chuỗi NORM; chạy lại test core TMATMUL có sẵn và test rowwise có sẵn với 1.307.712 so sánh lane.
- Guard: thiếu LUT phải bị từ chối.

`functional/` và `nonlinear/` chứa testbench của giao tiếp RMS 512 phần tử cũ (8/16 bit, stream, epsilon/rsqrt). Module `nonlinear_dispatch.sv` cũ cũng không thuộc đường thực thi hiện tại; core dùng `norm_dispatch.sv`. Các fixture cũ không phải oracle cho flow 32 phần tử này.

Đã kiểm tra bằng mô phỏng RTL ModelSim. Chưa chạy synthesis/STA: cây cộng + sqrt tổ hợp và 32 bộ chia tổ hợp cần đo lại tài nguyên và timing theo công nghệ/clock mục tiêu; không suy ra Fmax từ số chu kỳ mô phỏng.
