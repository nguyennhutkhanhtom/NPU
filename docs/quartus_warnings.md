# Kiểm tra warnings Quartus

Ngày 30/09/2026, project `matmul_free`, top `matmulfree`, Quartus Lite 18.1.

## Kết quả sau sửa

- Regression V2 pass ở nhánh thường, `SYNTHESIS`, và `SYNTHESIS` + `QUARTUS_SYNTHESIS`: 146 ca host, 47 kiểm tra SRAM, scalar, 393.216 vector sigmoid mỗi chế độ, kiểm tra LUT hợp lệ/thiếu/hỏng.
- Ctrl+K — Analysis & Synthesis thành công lúc 18:05:51: **0 errors, 1 warning**.
- Hash toàn bộ RTL khớp với source đã chạy regression.
- Synthesis riêng xác nhận descriptor có 1.024 thanh ghi, không có latch; SRAM 256×256 có đủ 65.536 bit block RAM.

| Chỉ số của toàn project | Trước sửa | Sau sửa |
|---|---:|---:|
| Warnings | 174 | 1 |
| Dedicated logic registers | 339.651 | 13.393 |
| Block memory bits | 6.656 | 334.336 |
| Logic cells sau synthesis | 473.104 | 29.809 |

## Những điểm đã sửa

1. **Matrix descriptor thành latch:** Quartus 18.1 suy luận sai các phép ghi từng phần vào packed struct với index thay đổi. Chuyển sang từng thanh ghi 32 bit, index hằng và write-enable riêng. Report mới không có thông báo inferred latch.
2. **SRAM lớn thành thanh ghi:** Chia SRAM Quartus thành tám bank 32 bit, mỗi bank có một cổng ghi toàn word và một cổng đọc synchronous. Mỗi bank có write-enable riêng cho lane mask; memory và register dữ liệu đọc không có asynchronous reset. Tổng SRAM parameter/workspace 327.680 bit đã vào block RAM; 6.656 bit còn lại là instruction memory.
3. **133 pin không có driver trong package function:** Gán đầy đủ các biến tạm của phép làm tròn cả khi shift bằng 0. Report mới không còn cảnh báo pin không có driver.
4. **Cắt bit và signed shift:** Viết rõ sized cast, hằng theo độ rộng thanh ghi và unsigned shift amount tại các phép chuyển đổi có chủ ý. Regression kiểm tra lại kết quả số học sau sửa.
5. **Khai báo và tối ưu synthesis:** Bỏ hai biến không dùng, khai báo state constants của `mem_burst` bằng `localparam`, chuyển synthesis effort sang `AUTO` để bật tối ưu theo timing.

## Warning còn lại

**276020 — instruction memory read-during-write:** Quartus thêm pass-through logic để duy trì đúng hành vi đọc khi ghi của mô hình RTL. Đây là thông báo về phần cứng bổ sung để bảo toàn chức năng. Regression host/instruction pass, không có lỗi chức năng được phát hiện liên quan đến warning này.

Report mới nằm tại `docs/quartus_synthesis.rpt`; kết quả và hash regression tại `../tests/results.json`. Kiểm tra suy luận phần cứng riêng bằng `quartus_sh -t tests/check_synthesis.tcl` từ thư mục gốc project.

Các kết quả trên xác nhận regression và Analysis & Synthesis. Khả năng đặt/routing và timing của thiết bị cần kết quả Fitter và Timing Analyzer riêng.
