# NPU ternary: toàn graph LLM trên RTL

> **Category: GUIDE.**

NPU này chạy trọn một mô hình ngôn ngữ nhỏ (NanoFable) bằng phần cứng. Top chính là
[`llm_soc.sv`](<Verilog Source code/llm_soc.sv>). Host nạp checkpoint, cấu hình và prompt;
RTL tự chạy prefill, bốn transformer layer, language head, chọn token và vòng sinh token.
`matmulfree.sv` là core instruction-driven cũ, giữ lại cho regression legacy.

Trạng thái hiện tại (Phase 1B): bảy nhóm regression PASS trên Xcelium và Questa; ứng dụng
pretrained chạy trực tiếp (chưa qua gated flow) cho 96/96 token khớp reference; timing Quartus
đạt 100 MHz ở cả bốn corner. Số liệu và bằng chứng:
[trạng thái kiểm chứng](docs/verification/optimization_status.md).

## Bắt đầu từ đâu

| Bạn cần | Đọc |
|---|---|
| Hiểu NPU từ đầu (có kiến thức nền) | [Source guide](docs/source_guide/README.md) → `00_kien_thuc_nen.md` |
| Kiến trúc và numeric contract | [Kiến trúc llm_soc](docs/design/full_rtl_language.md) |
| Nạp dữ liệu và điều khiển top | [Host interface](docs/design/host_interface.md) |
| Đọc một module RTL | [Danh mục module](docs/source_guide/README.md#danh-mục-file-rtl) |
| Chạy kiểm chứng | [Verification guide](docs/verification/README.md) |
| Chạy checkpoint thật | [Demo NanoFable](docs/demos/language.md) |
| Mọi tài liệu khác | [Mục lục tài liệu](docs/README.md) |

## Cấu trúc repository

```
README.md, AGENTS.md, TASK_STATE.md
Verilog Source code/   RTL và LUT (chỉ source, không có tài liệu)
docs/                  toàn bộ tài liệu
  source_guide/          tổng quan 00–03, modules/<module>.md, full graph
  design/                kiến trúc, host interface, ASIC, RTL style
  verification/          trạng thái, hướng dẫn chạy, timing, evidence
  demos/                 demo NanoFable và demo legacy
  diagrams/              sơ đồ draw.io/SVG và cách render
  history/, reviews/     lịch sử và review
tests/                 testbench, reference và runner
quartus/               project và constraint Quartus
tools/                 công cụ timing, tài liệu, LUT và checkpoint
release/               gói data trial bàn giao DFT/PD
```

## Quy tắc

[AGENTS.md](AGENTS.md) ghi quy tắc làm việc với RTL và tài liệu.
[TASK_STATE.md](TASK_STATE.md) ghi baseline đã kiểm chứng và việc tiếp theo.
Kết quả Quartus là bằng chứng FPGA; ASIC cần SRAM binding, thư viện và signoff riêng.
