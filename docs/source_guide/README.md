# Hướng dẫn source

> **Category: GUIDE.** Điều hướng RTL hiện tại mà không cần nạp các bản sao source listing.

| Bắt đầu từ | Mục đích |
|---|---|
| [Full graph](full_graph.md) | Top `llm_soc` hiện tại, trách nhiệm của module và tài nguyên dùng chung |
| [Tài liệu module (chính)](<../../Verilog Source code/doc/README.md>) | Tài liệu chi tiết từng module, nằm cạnh source |
| [Kiến trúc hiện tại](../design/full_rtl_language.md) | Model geometry, luồng inference và numeric contract |
| [Hierarchy legacy](legacy/README.md) | Core instruction/descriptor `matmulfree` |
| [Danh mục sơ đồ](../diagrams/README.md) | Hierarchy và diagram asset hiện có |

RTL là nguồn chuẩn cho chi tiết implementation. Hãy tìm state/signal cần thiết
trước khi đọc một module lớn. Trạng thái verification và implementation hiện tại:
[optimization status](../verification/optimization_status.md).
