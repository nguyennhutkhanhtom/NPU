# Lịch sử và tài liệu tham chiếu

[Tài liệu](../README.md) → **Lịch sử**

Trạng thái workspace nằm ở [verification status](../verification/optimization_status.md).
Các tài liệu dưới đây giữ quyết định, checkpoint hoặc báo cáo tại thời điểm viết.
Một câu “current” trong bản lưu cần được hiểu theo thời điểm của bản đó.

## Lịch sử thiết kế và kiểm chứng

| Trang | Phạm vi |
|---|---|
| [Phát triển full graph](full_rtl_development.md) | Các bước mở rộng, memory/pipeline và operator trước bản docs mới |
| [Timing development](timing_development.md) | Critical paths, fail/pass và đề xuất Quartus tại từng checkpoint |
| [Runner development](full_rtl_verification_development.md) | Các mốc memory models, license, compile và synthetic tests |
| [Review version 3](../reviews/rtl_change_review_v3.md) | Tối ưu throughput đã triển khai và các kết quả đo |
| [Implementation review](../reviews/implementation_review.md) | Tích hợp và sửa lỗi core legacy |
| [Demo legacy](../demos/legacy/README.md) | MNIST, NanoFable hybrid và khảo sát model cũ |
| [Task state 04/10/2026](task_state_20261004.md) | Snapshot giữ nguyên byte; links/commands dùng ngữ cảnh root khi tạo |
| [Project Quartus cũ](quartus_projects.md) | Vị trí 11 retired experiment folders |

## Archive và cleanup

| Record | Nội dung |
|---|---|
| [Archive gốc](history.zip) | 189 tài liệu/ảnh/công cụ từ research và review |
| [Cleanup manifest](cleanup_manifest.json) | Phân loại file và hashes của đợt sắp xếp ban đầu |
| [Helper cleanup 02/10](unused_cleanup_20261002.json) | Retired execution/migration files và commit phục hồi |
| [Helper cleanup 04/10](helper_cleanup1/manifest.json) | Hai helper cũ, ZIP byte-exact và SHA-256 |
| [Cache cleanup 02/10](cache_cleanup_20261002.json) | Cache legacy đã xóa, giữ model assets và evidence |
| [Quartus database cleanup 04/10](quartus_database_cleanup_20261004.json) | Database inactive đã xóa sau khi giữ source/report archives |
| [Workspace cleanup 05/10](workspace_cleanup_20261005.json) | Thu hồi 4,273 GiB; giữ nguyên các file được bảo vệ |
| [Implementation helper archive](optimization_implementation_20261005.md) | 17 one-shot helper/staging files đã lưu ZIP |
| [Arrangement 05/10](workspace_arrangement_20261005.json) | Di chuyển file và kiểm tra byte hashes |
| [Docs trước cập nhật 06/10](doc_refresh_20261006_before.zip) | 25 trang trước khi sửa nội dung/navigation; [hash record](doc_refresh_20261006_before.json) |
| [Render-cache cleanup](render_cache_cleanup_20261002.json) | Các render cũ đã xóa; diagram assets hiện có được giữ |

Archive gốc có SHA-256
`6d7e6b88f8d28863fc03b47593b3c4d9c0a60653f910ef7289315b6310d5f9fb`.
Source snapshots và raw verification evidence giữ tại các path ban đầu để
report hashes và provenance tiếp tục có thể kiểm tra.

## Thesis, poster, slide và bài báo

| File gốc | Vai trò |
|---|---|
| [Thesis / DTUT-242-13](references/DTUT-242-13.pdf) | Thesis gốc |
| [Poster](<references/Nguyen Nhut Khanh_poster.pdf>) | Poster thesis |
| [Slide](<references/Nguyen Nhut Khanh_ppt_thesis.pptx>) | Presentation thesis |
| [Scalable MatMul-free Language Modeling v5](references/2406.02528v5.pdf) | Bài báo tham chiếu cho ternary linear và MLGRU/GLU |

Các file tham chiếu gốc và raw evidence giữ nguyên byte. Đợt cập nhật sơ đồ ngày
06/10/2026 đã refresh source guide; bản tài liệu trước đợt này nằm tại
[diagram archive](../verification/diagrams_20261006/before.zip). Những minh họa
lịch sử vẫn được ghi rõ theo implementation của checkpoint tương ứng.
