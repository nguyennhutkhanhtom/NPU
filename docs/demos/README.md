# Demo model

[Tài liệu](../README.md) → **Demo**

## Chạy model trên llm_soc

| Bạn muốn làm gì? | Trang |
|---|---|
| Chạy checkpoint NanoFable thật, từng bước | [Hướng dẫn NanoFable](language.md) |
| Kiểm tra model shape và khả năng thay checkpoint | [Tương thích model](candidates.md) |
| Tải/kiểm tra asset đã pin | [NanoFable assets](../../tests/language_demo/README.md) |
| Xác nhận gate trước khi chạy | [Trạng thái kiểm chứng](../verification/optimization_status.md) |

`run_application.ps1` dùng checkpoint thật, tạo reference số nguyên để đối chiếu,
rồi mô phỏng toàn graph trên RTL. Host cấp parameters, prompt và cấu hình.
Output cần được đọc ở cả hai mức: token RTL/reference có khớp hay không và văn
bản đã decode có mạch lạc hay không.

**Tại lần cập nhật 06/10/2026:** chưa có application PASS; cấu hình QSF hiện tại
đang chờ timing manifest khớp. Hướng dẫn đã sẵn sàng, nhưng phải qua gate trước
khi chạy export/reference hoặc application.

## Kết quả demo legacy

[Danh mục legacy](legacy/README.md) giữ kết quả Binary-MNIST160, NanoFable hybrid
và khảo sát model cho core matmulfree. Các số liệu này gắn với runner và source
được ghi trong báo cáo, không được dùng làm kết quả pretrained của llm_soc.
