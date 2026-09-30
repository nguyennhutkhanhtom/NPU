# Tài liệu giữ cho source chính

`../Verilog Source code` là nguồn duy nhất đang phát triển. Source chính và thư mục `docs` được quản lý trên GitHub. Test trong `../tests` và project Quartus trong `../quartus` được giữ local, không nằm trong bản clone từ GitHub.

- [Interface, ISA, descriptor, host map và LUT](<../Verilog Source code/README.md>).
- [Giải thích kiến trúc và từng khối RTL](source_guide/README.md), kèm manifest SHA-256 và `validate.py` để phát hiện source thay đổi.
- [Mục tiêu kiến trúc, bit-width và SRAM](architecture.md).
- [Các mô hình demo phù hợp và giới hạn](model_candidates.md).
- [Các lỗi đã sửa khi tích hợp vào source chính](implementation_review.md).
- [Kết quả và warnings Quartus](quartus_warnings.md), [report synthesis](quartus_synthesis.rpt) và [summary](quartus_synthesis.summary).
- Cách chạy và chọn test: xem `tests/README.md` trong workspace local.
- [Thông tin lịch sử cần tra cứu](history.zip) và [manifest cleanup](cleanup_manifest.json): giữ nguyên Markdown, JSON, công cụ tạo tài liệu, patch và ảnh từ `research`/`review`, đã đối chiếu SHA-256. Các file trong archive là lịch sử, không dùng để compile source chính.

Các báo cáo synthesis là kết quả ngày 30/09/2026, chưa gồm Fitter/STA của FPGA hoặc physical design ASIC. Chú giải RTL là snapshot; chạy `python docs/source_guide/validate.py` sau khi sửa source để kiểm tra độ khớp.

Snapshot chú giải ngày 29/09 đã có khác biệt với các sửa đổi Quartus ngày 30/09. Validator giữ việc báo lệch source; README source chính và báo cáo Quartus mô tả cấu hình mới nhất.

Các PDF/PPT gốc được giữ tại thư mục gốc workspace để tra cứu thesis, poster, slide và bài báo 2406.02528v5. Đợt cleanup bỏ source trùng `npu_asic_v2`, các snapshot/test interface cũ, LUT v1 và cache/log dư thừa; giữ test hiện hành và những ca biên còn hữu ích trong `tests/tb_all.sv`.
