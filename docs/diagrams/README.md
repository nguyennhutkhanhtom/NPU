# Sơ đồ RTL và cách đọc

> **Category: GUIDE.**

[Tài liệu](../README.md) → **Sơ đồ RTL**

Top chính là **llm_soc**. Sơ đồ hierarchy liệt kê instance thực, còn functional
overview giải thích các FSM, mux, register và luồng xử lý nằm trong top.
`matmulfree` dùng host contract và ISA riêng; các sơ đồ của nó thuộc phần legacy.

## Chọn sơ đồ theo mục đích

| Muốn xem | Tài liệu hoặc file |
|---|---|
| Instance, module con và generate scope | [rtl_hierarchy.drawio](../../rtl_hierarchy.drawio) |
| Hierarchy khi USE_QUARTUS_MEMORY=0 | [rtl_hierarchy_portable.drawio](rtl_hierarchy_portable.drawio) |
| Engine, tài nguyên dùng chung và mux ở top | [Full graph overview](../source_guide/full_graph.md#sơ-đồ-tài-nguyên-và-đường-dữ-liệu) |
| Prefill, bốn layer, token selection và decode | [Luồng inference](../design/full_rtl_language.md#luồng-inference) |
| Request/ACK, cancellation và parameter commit | [Host transaction](../design/host_interface.md#một-transaction) |
| Cache reuse và invalidate | [Cache reuse and ownership](../design/exact_throughput_optimization.md#cache-reuse-and-ownership) |
| Sơ đồ từng module, numeric stages và code hiện tại | [Danh mục 41 RTL/LUT assets](../source_guide/blocks/README.md) |
| Core dùng instruction/descriptor | [Hierarchy matmulfree](<../source_guide/legacy/README.md>) |

## Các tab hierarchy

| Tab | Nội dung |
|---|---|
| 00_TOP | Top, host request/acknowledge, clock/reset và status/debug |
| 01_LEVEL_1 | Các instance trực tiếp; xem thêm các kết nối chức năng ở cuối phần block |
| 02_LEVEL_2 | Lane banks, 128 byte multipliers, ternary dot, private dividers và sigmoid helpers |
| 03_LEVEL_3 | SRAM technology leaves; parameter banks sâu chia 24 tile mỗi lane |
| 04_LEVEL_4 | altsyncram: external Quartus library primitive; chỉ có trong bản Quartus |

Các instance lặp có block riêng. Generate scope đặt ngoài block; tên trong block
luôn gồm hai dòng: instance và `(module)`. Panel **Block Functions & Interfaces**
giải thích các block, source references và những range generate bao phủ chúng.
[Manifest](hierarchy_manifest.json) liệt kê từng full path, parent, tham số và
port mapping trong source, để tra những instance có cùng tên cục bộ.

Hierarchy Quartus có 749 instance kể cả top và 256 external `altsyncram`;
hierarchy portable có 589 instance kể cả top. Đây là số instance trong expansion
đã phân tích, không phải số tài nguyên sau synthesis. Các trang sâu dài vì vẫn
giữ từng instance riêng; dùng zoom/search trong diagrams.net để đọc từng nhóm.

## Quy ước và cấu hình

Markdown Mermaid diagrams follow the [shared diagram style](diagram_style.md): semantic colors, dark text, white background and approximately 17 px text. The existing draw.io hierarchy retains its black/white 18 pt presentation. Trong draw.io,
arrow mảnh biểu diễn instantiation; arrow đậm có nhãn biểu diễn kết nối chức năng
đã trace. Outline đứt đoạn đánh dấu primitive ngoài source repository.

Cấu hình: USE_QUARTUS_MEMORY=1 hoặc 0, ATTN_DIV_LANES=4, SIGMOID_LANES=4,
PERF_COUNTERS=0, ENABLE_DEBUG_INDEX=0. Normalizer dùng USE_SHARED=1: lane zero
nối tới u_div của top; ba lane còn lại là child instances. Package và generate
scope không được tính thành module instance.

Host là interface request/acknowledge nội bộ, không được gán nhãn APB hay AXI.
Head và QK gửi request/issue qua mux của parent. Linear dùng ternary_dot32 riêng.
SRAM portable là behavior model có thể thay bằng ASIC binding; Quartus là EDA
demonstration backend, không phải ASIC signoff.

## Preview và kiểm tra

| Quartus hierarchy | Portable hierarchy |
|---|---|
| [00_TOP](rtl_hierarchy_00_TOP.svg) | [00_TOP](rtl_hierarchy_portable_00_TOP.svg) |
| [01_LEVEL_1](rtl_hierarchy_01_LEVEL_1.svg) | [01_LEVEL_1](rtl_hierarchy_portable_01_LEVEL_1.svg) |
| [02_LEVEL_2](rtl_hierarchy_02_LEVEL_2.svg) | [02_LEVEL_2](rtl_hierarchy_portable_02_LEVEL_2.svg) |
| [03_LEVEL_3](rtl_hierarchy_03_LEVEL_3.svg) | [03_LEVEL_3](rtl_hierarchy_portable_03_LEVEL_3.svg) |
| [04_LEVEL_4](rtl_hierarchy_04_LEVEL_4.svg) | Không có vendor primitive |

SVG preview được tạo từ cùng label và geometry của file draw.io. Source XML
vẫn là artifact chỉnh sửa chính. [Preview validation](preview_validation.json)
ghi render từng trang; [Mermaid validation](../source_guide/diagram_validation.json)
ghi hash và render của tất cả Mermaid blocks trong docs.
[Kết quả kiểm tra](../verification/diagrams_20261006/results.json) ghi coverage,
XML, source references, fonts, preview và các source hashes được giữ nguyên.

Hình MNIST trong demo là ảnh input minh họa, không phải sơ đồ RTL. Các sơ đồ
trong history/review vẫn ghi phạm vi implementation của bản lịch sử; bản trước
đợt chỉnh sửa được lưu tại [before.zip](../verification/diagrams_20261006/before.zip).

[Công cụ render](../../tools/docs/README.md) · [Source validator](../source_guide/validate.py)
