# NPU ternary: toàn graph LLM trên RTL

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

## Cấu hình đang hỗ trợ

| Thành phần | Cấu hình |
|---|---|
| Model | NanoFable-1M-ternary, checkpoint seed1 đã pin |
| Graph | 4 layer, 128 channel, 4 attention head, FFN 384 channel |
| Vocabulary và context | 4.096 token; tối đa 128 vị trí gồm prompt và continuation |
| Bộ nhớ | Parameter 768 KiB; KV 384 KiB; vector workspace 9 KiB |
| Compute/control | SystemVerilog portable; phép nhân/chia bằng logic cấu trúc |
| Backend | Quartus để demo synthesis, fit và timing; SRAM leaf có thể thay bằng công nghệ ASIC |

## Kết quả và phạm vi

Regression tổng hợp `opt_final4` đã PASS bảy nhóm. Graph cần **1.066.965 compute
clocks**, giảm **74,92%** so với baseline 4.254.046 clocks; ba token được kiểm tra
khớp giá trị kỳ vọng. Checkpoint timing `opt_fulltop7` đạt **100,78 MHz**,
worst setup **+0,077 ns**, mọi slack không âm, TNS = 0 và không có path unconstrained.

Các kết quả trên áp dụng cho source/config được lưu trong từng manifest.
**Cập nhật 06/10/2026:** RTL vẫn khớp regression; QSF đã khác cấu hình của
`opt_fulltop7`. Chưa có manifest hoàn tất cho lượt timing mới và chưa có kết quả
PASS của application pretrained. Đọc [trạng thái kiểm chứng](docs/verification/optimization_status.md)
trước khi chạy model thật. Token matching và chất lượng văn bản là hai mục đánh giá riêng.

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
