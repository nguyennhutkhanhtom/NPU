# Đọc và tái tạo timing full-top

[Tài liệu](../../README.md) → [Kiểm chứng](../README.md) → **Timing**

Timing hiện tại cần đọc cùng [trang trạng thái](../optimization_status.md).
Trang này mô tả quy trình và cách hiểu một checkpoint đã hoàn tất.

## Chọn đúng top và configuration

Full graph dùng `quartus/llm_soc.qpf`, QSF và SDC đi kèm. `matmul_free` là project
legacy. Report timing của core legacy không xác minh toàn graph llm_soc.

Source/config hashes phải khớp workspace. Ví dụ `opt_fulltop7` có RTL khớp
regression hiện tại nhưng QSF đã khác; Fmax của archive vẫn là kết quả hợp lệ
cho checkpoint đó, còn gate application hiện tại cần manifest configuration mới.

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

## Checkpoint tối ưu đã hoàn tất

[opt_fulltop7 manifest](opt_fulltop7/manifest.json) ghi:

| Corner | Fmax MHz | Setup ns | Hold ns | Recovery ns | Removal ns | Pulse ns |
|---|---:|---:|---:|---:|---:|---:|
| Slow 85 °C | 100,78 | 0,077 | 0,245 | 0,123 | 1,599 | 3,600 |
| Slow 0 °C | 101,50 | 0,148 | 0,232 | 0,332 | 3,666 | 3,548 |
| Fast 85 °C | 148,41 | 3,262 | 0,131 | 4,535 | 2,330 | 3,801 |
| Fast 0 °C | 161,60 | 3,812 | 0,115 | 5,473 | 0,976 | 3,790 |

Mọi TNS bằng 0; unconstrained counts bằng 0. Fit dùng 59.605 ALMs, 66.924
registers, 1.186 RAM blocks và 0 DSP. Worst setup margin +0,077 ns nhỏ, nên các
thay đổi tiếp theo cần fresh timing evidence.

Warnings được giữ trong report. Pin assignments và LogicLock license thuộc
backend EDA; việc chấp nhận các warning đã review không thay thế các điều kiện
slack, TNS hay unconstrained checks. Xem [warning review NanoFable](../warning_review_nanofable_20261005.md).

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
