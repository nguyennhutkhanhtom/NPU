# Lịch sử và tài liệu gốc

[Project](../../README.md) → [Tài liệu](../README.md) → **Lịch sử**

Thiết kế đang phát triển được mô tả trong [kiến trúc hiện hành](../design/architecture.md), [interface](../design/interfaces.md) và [RTL guide](../source_guide/README.md). Các mục ở đây phục vụ tra cứu các quyết định và nguồn gốc; snapshot cũ không tham gia build.

## Quyết định và sửa lỗi

| Tài liệu | Phạm vi |
|---|---|
| [Design review hiện hành](../reviews/design_review.md) | Cải tiến, bit-width, reset/valid, regression và số liệu trước/sau |
| [Implementation review](../reviews/implementation_review.md) | Các lỗi từ bản v2 ban đầu và quá trình tích hợp/thống nhất RTL |
| [History archive](history.zip) | 189 tài liệu/ảnh/công cụ lịch sử từ `research` và `review`, giữ nội dung nguyên vẹn |
| [Unused-helper cleanup 02/10/2026](unused_cleanup_20261002.json) | 11 retired execution/migration files; hashes and recoverable Git commit |
| [Unused-cache cleanup 02/10/2026](cache_cleanup_20261002.json) | Six untracked retired-demo caches,1.29GB freed; current model/assets/evidence retained |
| [Cleanup manifest](cleanup_manifest.json) | Phân loại file, SHA-256 và thông tin đối chiếu archive |

Archive có SHA-256 `6d7e6b88f8d28863fc03b47593b3c4d9c0a60653f910ef7289315b6310d5f9fb`. Nội dung archive được giữ nguyên khi sắp xếp lại tài liệu ngày 01/10/2026.

## Thesis, poster, slide và bài báo

| Tài liệu gốc | Vai trò |
|---|---|
| [Thesis / DTUT-242-13](references/DTUT-242-13.pdf) | Tài liệu thesis gốc |
| [Poster](<references/Nguyen Nhut Khanh_poster.pdf>) | Poster thesis |
| [Slide](<references/Nguyen Nhut Khanh_ppt_thesis.pptx>) | Presentation thesis |
| [Scalable MatMul-free Language Modeling v5](references/2406.02528v5.pdf) | Bài báo tham chiếu cho ternary linear, NORM và MLGRU/GLU |

Các file gốc được chuyển thư mục và giữ nguyên byte. [Phần so sánh với thesis](../source_guide/README.md#8-khác-gì-so-với-thesis-của-bạn) giải thích khác biệt với core hiện hành.

[Về mục lục tài liệu](../README.md)
