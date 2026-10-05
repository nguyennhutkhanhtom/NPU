# Mục lục tài liệu

[Project](../README.md) → **Tài liệu**

Thiết kế hiện tại dùng top `llm_soc`. Tài liệu được đọc theo thứ tự dưới đây;
các trang legacy và báo cáo lịch sử có nhãn riêng để tránh nhầm phạm vi.

## Lộ trình đọc

| Bước | Nội dung | Trang chính |
|---|---|---|
| 1 | Hiểu top, graph, dữ liệu và bộ nhớ | [Kiến trúc llm_soc](design/full_rtl_language.md) |
| 2 | Hiểu host và trách nhiệm của từng module | [Host interface](design/host_interface.md), [full graph RTL](source_guide/full_graph.md) |
| 3 | Xác nhận evidence áp dụng cho source/config đang dùng | [Trạng thái kiểm chứng](verification/optimization_status.md) |
| 4 | Nạp checkpoint và chạy inference | [Demo NanoFable](demos/language.md) |
| 5 | Đọc kết quả, debug hoặc tái kiểm chứng | [Hướng dẫn verification](verification/README.md), [timing](verification/timing/README.md) |

## Các nhóm tài liệu

| Nhóm | Nội dung |
|---|---|
| [Thiết kế](design/README.md) | Graph, numeric formats, host, tối ưu throughput và ranh giới SRAM ASIC |
| [Source guide](source_guide/blocks/README.md) | Danh mục RTL hiện tại và các trang chú giải đã lưu |
| [Kiểm chứng](verification/README.md) | Regression, timing, evidence và điều kiện chạy pretrained |
| [Demo](demos/README.md) | Cách chạy model thật, đọc output và chọn checkpoint tương thích |
| [Review](reviews/README.md) | Thay đổi đã triển khai, lý do và kết quả đo |
| [Lịch sử](history/README.md) | Các mốc cũ, archive, cleanup và tài liệu tham chiếu |

## Tra cứu nhanh

| Câu hỏi | Đọc ở đâu? |
|---|---|
| File chính là llm_soc hay matmulfree? | [Top và module](source_guide/full_graph.md#top-và-cấu-hình) |
| Graph và SRAM có kích thước bao nhiêu? | [Cấu hình và bộ nhớ](design/full_rtl_language.md#cấu-hình-và-bộ-nhớ) |
| Host chờ ACK và đọc output thế nào? | [Host interface](design/host_interface.md) |
| Mô phỏng có chạy model thật chưa? | [Trạng thái hiện tại](verification/optimization_status.md) |
| Lệnh chạy demo là gì? | [Các bước chạy NanoFable](demos/language.md#các-bước-chạy) |
| Có thể thay bằng model khác không? | [Tương thích model](demos/candidates.md) |
| Khi nào cần chạy lại timing hoặc units? | [Evidence và thay đổi source](verification/README.md#khi-nào-cần-chạy-lại) |
| Muốn xem core 32 PE cũ? | [Thiết kế legacy](design/README.md#thiết-kế-legacy) |

## Đọc số liệu đúng phạm vi

Trạng thái mới nhất tập trung tại [optimization_status.md](verification/optimization_status.md).
README và các trang hướng dẫn dẫn tới trang này thay vì coi một kết quả cũ là
bằng chứng cho mọi phiên bản source/config.

- Regression tổng hợp kiểm tra số học, protocol và graph với fixture.
- Application pretrained nạp checkpoint thật và đối chiếu token RTL với reference.
- Văn bản có mạch lạc hay không cần được đọc và đánh giá riêng.
- Timing Quartus xác minh backend EDA; ASIC signoff thuộc flow công nghệ khác.

Các sơ đồ và code excerpts trong source guide đã được đối chiếu với RTL ngày
06/10/2026. [Mục lục sơ đồ](diagrams/README.md) cung cấp hierarchy chỉnh sửa được,
functional overview và các sơ đồ operator. Bản trước cập nhật được lưu riêng.

## Thuật ngữ dùng chung

| Thuật ngữ | Cách hiểu trong tài liệu |
|---|---|
| Graph | Toàn chuỗi các phép tính của model, từ embedding đến token selection |
| Pretrained application | Inference dùng checkpoint đã train, khác với fixture tổng hợp |
| Reference | Implementation số nguyên độc lập để tính kết quả kỳ vọng |
| Gate | Bước kiểm tra các điều kiện phải đạt trước khi chạy model thật |
| Evidence | Manifest, logs, source/config hashes và reports của một lượt kiểm chứng |
| Snapshot | Bản lưu tại một thời điểm; đọc theo source/config và ngày được ghi |

## Sơ đồ RTL

[Mục lục sơ đồ](diagrams/README.md) dẫn tới hierarchy llm_soc có thể chỉnh sửa, nhánh SRAM portable, functional overview và các sơ đồ operator.
