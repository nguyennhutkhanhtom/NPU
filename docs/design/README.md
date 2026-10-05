# Thiết kế

[Tài liệu](../README.md) → **Thiết kế**

## Thiết kế llm_soc hiện tại

| Thứ tự | Trang | Nội dung |
|---|---|---|
| 1 | [Toàn graph](full_rtl_language.md) | Model shape, các bước inference, format số và bộ nhớ |
| 2 | [Host interface](host_interface.md) | Ports, memory map, handshake, reset và trình tự chạy |
| 3 | [Tối ưu throughput](exact_throughput_optimization.md) | Cache, streaming, resource ownership và traffic |
| 4 | [ASIC portability](asic_portability.md) | Logic portable và giới hạn technology binding |
| 5 | [SRAM binding](asic_memory_binding.md) | Hợp đồng cần giữ khi thay SRAM leaf |
| 6 | [Quy tắc viết RTL](rtl_style.md) | Cấu trúc phần cứng rõ ràng, register ownership và coding policy |

Sau khi hiểu kiến trúc, mở [danh mục module](../source_guide/blocks/README.md)
hoặc [hướng dẫn chạy NanoFable](../demos/language.md).

## Thiết kế legacy

| Trang | Phạm vi |
|---|---|
| [Kiến trúc matmulfree](architecture.md) | Core instruction-driven 32 PE; parameter 32 KiB và workspace 8 KiB |
| [ISA và interface matmulfree](interfaces.md) | Opcode, descriptor, dynamic scale và host map của core cũ |
| [Hierarchy đã lưu](../source_guide/README.md) | Luồng NORM, TMATMUL, vector operations và sơ đồ legacy |

Các interface và dung lượng của core legacy thuộc top `matmulfree`, còn
`llm_soc` dùng graph cố định và host map ở trang riêng phía trên.

## Nghiên cứu và quyết định

[Architecture research](architecture_research.md) ghi baseline và các mốc được
nêu trong tài liệu. [Review version 3](../reviews/rtl_change_review_v3.md) ghi
implementation tối ưu và số liệu đã đo; [trạng thái kiểm chứng](../verification/optimization_status.md)
cho biết evidence nào còn áp dụng cho workspace.
