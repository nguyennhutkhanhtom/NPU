# Đọc và tái tạo timing full-top

> **Category: GUIDE.**

[Tài liệu](../../README.md) → [Kiểm chứng](../README.md) → **Timing**

Timing hiện tại cần đọc cùng [trang trạng thái](../optimization_status.md).
Trang này mô tả quy trình và cách hiểu một checkpoint đã hoàn tất.

## Chọn đúng top và configuration

Full graph dùng `quartus/llm_soc.qpf`, QSF và SDC đi kèm. `matmul_free` là project
legacy. Report timing của core legacy không xác minh toàn graph llm_soc.

## Lệnh đo

Chạy từ repository root, dùng tag chưa có:

```powershell
& tools/timing/run.ps1 -Project quartus/llm_soc -Tag my_timing_20261006 -QuartusBin C:/altera_lite/25.1std/quartus/bin64 -Python C:/Users/khanh/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe
```

Không sửa RTL, QSF/QPF hoặc SDC trong lúc build. Chỉ coi một lượt là hoàn tất
sau khi synthesis, fit, STA, extraction và manifest đều được ghi thành công.
Map PASS hoặc fit PASS riêng lẻ chưa chứng minh timing closure.

## Các chỉ tiêu cần đọc

| Chỉ tiêu | Ý nghĩa / điều kiện gate |
|---|---|
| Minimum restricted Fmax | Ít nhất 100 MHz cho full-top; đọc các corner được gate kiểm tra |
| Setup slack | Margin dữ liệu tới trước clock edge; không âm |
| Hold slack | Margin dữ liệu giữ sau clock edge; không âm |
| Recovery/removal | Ràng buộc nhả reset; không âm |
| Pulse-width slack | Độ rộng xung hợp lệ; không âm |
| TNS | Tổng slack âm của một check; phải bằng 0 |
| Unconstrained counts | Path, clock và ports phải được constraint; mọi count gate kiểm tra bằng 0 |
| Fitted resources | ALMs/registers/RAM và hard blocks của bản fit thực tế |

Gate yêu cầu cả bốn corner slow/fast, 1.100 mV, 0 °C/85 °C đạt setup, hold,
recovery, removal và pulse. Resource report cũng cần DSP/PLL/DLL/HSSI bằng 0.
Không dùng timing exception để che failure.

## Current results

[Optimization status](../optimization_status.md) owns current Fmax, slack, resources and evidence. [Historical throughput review](../../reviews/rtl_change_review_v3.md) preserves the earlier checkpoint.

## Những file cần giữ

Một timing archive gồm manifest, commands, source/config snapshot hoặc ZIP,
map/fit/STA reports, extracted corner checks và unconstrained report.
`check_gate.py` kiểm tra report hashes trước khi dùng metrics. Thư mục db và
incremental_db có thể tái tạo; evidence gốc phải được giữ nguyên.

## Lịch sử và giới hạn

[Lịch sử timing](../../history/timing_development.md) giữ các mốc fail/pass cũ,
critical paths và đề xuất Quartus tại thời điểm đo. [Review version 3](../../reviews/rtl_change_review_v3.md)
ghi thay đổi RTL và resource tradeoff của tối ưu.

Quartus là backend demo EDA, không phải ASIC signoff. ASIC cần library,
SRAM technology binding, constraints và physical implementation riêng.
