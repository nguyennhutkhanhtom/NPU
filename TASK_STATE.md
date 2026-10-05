# Checkpoint workspace

Cập nhật **06/10/2026**, Asia/Saigon. Source, manifest và log là bằng chứng gốc;
giữ các thay đổi đúng và evidence theo [AGENTS.md](AGENTS.md).

## Trạng thái cần nhớ

- Top hiện tại: llm_soc. Core matmulfree thuộc legacy.
- 41 RTL/LUT assets khớp all-seven PASS opt_final4; graph tổng hợp 1.066.965 compute clocks.
- opt_fulltop7 timing PASS 100,78 MHz cho configuration trong archive.
- QSF hiện tại đã khác opt_fulltop7; application gate cần fresh timing manifest khớp.
- Workflow nanofable_long_20261005 ghi TIMING_RUNNING; tại lần rà soát chưa có manifest hoàn tất hoặc application PASS.

## Trang bắt đầu

| Cần làm | Trang |
|---|---|
| Hiểu graph và top | [Kiến trúc](docs/design/full_rtl_language.md) |
| Chạy model thật | [NanoFable từng bước](docs/demos/language.md) |
| Xem gate và evidence | [Trạng thái kiểm chứng](docs/verification/optimization_status.md) |
| Chạy lại units/timing | [Verification guide](docs/verification/README.md) |
| Đọc module | [Source overview](docs/source_guide/full_graph.md) |
| Xem lịch sử | [History](docs/history/README.md) |

Đợt cập nhật này sửa tài liệu và navigation. Sơ đồ/code excerpts giữ ở snapshot
đã ghi, chờ cập nhật riêng. Không thay RTL, runner hoặc configuration và không
thực thi pretrained inference trong công việc cập nhật docs.
