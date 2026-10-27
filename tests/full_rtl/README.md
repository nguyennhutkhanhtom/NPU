# Testbench và runner cho llm_soc

> **Category: GUIDE.** Điểm vào ngắn. Chi tiết testbench, cách application chạy, monitor và
> quy tắc library/evidence: [Full RTL tests](../../docs/verification/full_rtl_tests.md).
> Lệnh đầy đủ: [verification guide](../../docs/verification/README.md).

Đọc [trạng thái hiện tại](../../docs/verification/optimization_status.md) trước khi chạy lại.

| Runner | Công việc |
|---|---|
| `run_units.ps1` | Bảy nhóm synthetic units/graph (`-OnlyTop` để debug một nhóm) |
| `run_host_cancel_100mhz.ps1` | Probe host cancel/commit/ACK |
| `run_portable_100mhz.ps1` | Elaborate full top không dùng vendor module |
| `run_application.ps1` | Checkpoint thật qua toàn graph; xem [hướng dẫn NanoFable](../../docs/demos/language.md) |
| `check_gate.py`, `memory_model.py` | Kiểm tra gate và chuẩn bị RAM library của Quartus |

Dùng `WorkLibraryName` và `EvidenceTag` mới cho mỗi lượt; archive kết quả trước lượt kế tiếp.
