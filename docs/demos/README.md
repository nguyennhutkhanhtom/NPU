# Model demo

[Project](../../README.md) → [Tài liệu](../README.md) → **Model demo**

Các trang dưới đây nối checkpoint và graph với format/memory của core, rồi ghi cách kiểm chứng. Kết quả mô phỏng RTL được đối chiếu với reference số nguyên; chất lượng model gốc và sai số sau export được ghi riêng.

| Demo / tài liệu | Đọc để biết |
|---|---|
| [Binary-MNIST160](mnist.md) | Checkpoint đã train, 10 ảnh mẫu, 40 lượt tầng bit-exact, memory và chu kỳ graph |
| [NanoFable-1M-ternary](language.md) | CPU: 3 prompt × 32 token, deterministic repeat; RTL: 168 lượt linear, 33.792 output S32 bit-exact |
| [Model candidates](candidates.md) | Tính tương thích operator, K, memory và các cấu hình mở rộng |

## Application hiện tại

Mọi application ngôn ngữ mới dùng [full RTL runner](../../tests/full_rtl/README.md)
sau khi source hiện tại đạt synthesis, fitting, timing ≥100 MHz ở mọi corner và
sáu nhóm unit test. [NanoFable asset setup](../../tests/language_demo/README.md) tải
checkpoint/tokenizer đã pin; không thực thi model.

Runner MNIST và hybrid NanoFable cũ đã được loại bỏ. Các bảng/report ở trên giữ
kết quả lịch sử, với CPU generation và linear-only RTL được phân biệt rõ.
[Cleanup manifest](../history/unused_cleanup_20261002.json) ghi file/hash và commit phục hồi.

## Đọc trước khi export model mới

1. [Kiến trúc và format số](../design/architecture.md): kiểm tra K≤512, operator và dung lượng SRAM.
2. [Instruction, descriptor và scale](../design/interfaces.md): xác định tensor layout và chương trình.
3. [NORM, ternary và vector unit](../source_guide/README.md): hiểu điểm làm tròn/bão hòa và dữ liệu trung gian.
4. [Regression](../verification/README.md): kiểm tra RTL trước khi chạy checkpoint.

[Về mục lục tài liệu](../README.md) · [Xem design review](../reviews/design_review.md)
