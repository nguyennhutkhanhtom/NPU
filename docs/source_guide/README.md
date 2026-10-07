# Hướng dẫn source

> **Category: GUIDE.** Điều hướng RTL hiện tại mà không cần nạp các bản sao source listing.

| Bắt đầu từ | Mục đích |
|---|---|
| [Full graph](full_graph.md) | Top `llm_soc` hiện tại, trách nhiệm của module và tài nguyên dùng chung |
| [Danh mục theo module](blocks/README.md) | Liên kết source và chú giải ngắn gọn cho từng block |
| [Kiến trúc hiện tại](../design/full_rtl_language.md) | Model geometry, luồng inference và numeric contract |
| [Hierarchy legacy](legacy/README.md) | Core instruction/descriptor `matmulfree` |
| [Danh mục sơ đồ](../diagrams/README.md) | Hierarchy và diagram asset hiện có |

RTL là nguồn chuẩn cho chi tiết implementation. Hãy tìm state/signal cần thiết
trước khi đọc một module lớn. Trạng thái verification và implementation hiện tại:
[optimization status](../verification/optimization_status.md).
