# NPU ternary: toàn graph LLM trên RTL

**Flow chạy hiện tại:** [Xcelium/Genus trên Linux Slurm](tools/server/README.md). Các backend local đã ngừng hoạt động trên branch `remote`.


> **Category: GUIDE.**

Top chính là [`llm_soc.sv`](<Verilog Source code/llm_soc.sv>). Host nạp checkpoint,
cấu hình và prompt; RTL chạy prefill, bốn transformer layer, language head,
chọn token và vòng sinh token tiếp theo. `matmulfree.sv` là core instruction-driven
được giữ cho thiết kế và regression legacy.

**Bắt đầu tại [mục lục tài liệu](docs/README.md)** hoặc
**[hướng dẫn chạy NanoFable](docs/demos/language.md)**.

## Đọc theo nhu cầu

| Bạn cần làm gì? | Trang nên đọc |
|---|---|
| Hiểu thiết kế hiện tại | [Kiến trúc llm_soc](docs/design/full_rtl_language.md) |
| Nạp dữ liệu và điều khiển top | [Host interface](docs/design/host_interface.md) |
| Tìm module và đọc RTL | [Các khối của full graph](docs/source_guide/full_graph.md) |
| Chạy checkpoint thật | [Demo NanoFable từng bước](docs/demos/language.md) |
| Kiểm tra source, timing và kết quả | [Trạng thái kiểm chứng](docs/verification/optimization_status.md) |
| Tra cứu core cũ | [Tài liệu legacy](docs/design/README.md#thiết-kế-legacy) |

## Architecture and verification

[Current architecture](docs/design/full_rtl_language.md) owns model geometry and numerical contracts. [Current verification and implementation status](docs/verification/optimization_status.md) owns checkpoint results and evidence.

## Bố trí repository

| Vị trí | Nội dung |
|---|---|
| [Verilog Source code](<Verilog Source code/README.md>) | RTL và LUT dùng để compile |
| [docs](docs/README.md) | Kiến trúc, hướng dẫn, kiểm chứng, review và lịch sử |
| [tests](tests/README.md) | Testbench, reference và runner |
| [quartus](quartus/README.md) | Cấu hình backend; project cũ trong archive |
| [tools](tools/README.md) | Công cụ tài liệu, timing, LUT và checkpoint |

Các kết quả Quartus là bằng chứng cho backend EDA này; ASIC cần SRAM binding,
library và quy trình signoff riêng. [AGENTS.md](AGENTS.md) ghi quy tắc RTL;
[TASK_STATE.md](TASK_STATE.md) dẫn tới checkpoint và công việc đang chờ.
