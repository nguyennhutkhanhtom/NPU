# Model demo

[Project](../../README.md) → [Tài liệu](../README.md) → **Model demo**

Các trang dưới đây nối checkpoint và graph với format/memory của core, rồi ghi cách kiểm chứng. Kết quả mô phỏng RTL được đối chiếu với reference số nguyên; chất lượng model gốc và sai số sau export được ghi riêng.

| Demo / tài liệu | Đọc để biết |
|---|---|
| [Binary-MNIST160](mnist.md) | Checkpoint đã train, 10 ảnh mẫu, 40 lượt tầng bit-exact, memory và chu kỳ graph |
| [NanoFable-1M-ternary](language.md) | CPU: 3 prompt × 32 token, deterministic repeat; RTL: 168 lượt linear, 33.792 output S32 bit-exact |
| [Model candidates](candidates.md) | Tính tương thích operator, K, memory và các cấu hình mở rộng |

## Chạy lại

```powershell
./tests/model_demo/run.ps1
./tests/language_demo/run.ps1
```

[Runner MNIST](../../tests/model_demo/README.md) và [runner ngôn ngữ](../../tests/language_demo/README.md) mô tả dependency và asset đã pin. Các script, fixture nhẹ và results manifest được quản lý trên GitHub; checkpoint/runtime/packages được tải hoặc tạo local. Mỗi báo cáo demo ghi nguồn, checksum và lệnh chạy của riêng model đó.

NanoFable sinh văn bản toàn graph trên CPU. RTL chỉ replay các linear ternary với activation thực được ghi lại; affine RMSNorm, RoPE, attention, gating và output head vẫn ở CPU. [Báo cáo ngôn ngữ](language.md) ghi phạm vi, streaming SRAM, checksum và kết quả riêng.

## Đọc trước khi export model mới

1. [Kiến trúc và format số](../design/architecture.md): kiểm tra K≤512, operator và dung lượng SRAM.
2. [Instruction, descriptor và scale](../design/interfaces.md): xác định tensor layout và chương trình.
3. [NORM, ternary và vector unit](../source_guide/README.md): hiểu điểm làm tròn/bão hòa và dữ liệu trung gian.
4. [Regression](../verification/README.md): kiểm tra RTL trước khi chạy checkpoint.

[Về mục lục tài liệu](../README.md) · [Xem design review](../reviews/design_review.md)
