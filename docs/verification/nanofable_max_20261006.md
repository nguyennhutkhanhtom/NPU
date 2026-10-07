# Full-top timing và demo NanoFable ở context tối đa của RTL

> **Category: HISTORICAL SNAPSHOT — 2026-10-06.** Results below refer only to this saved run; use [current status](optimization_status.md) for workspace applicability.

[Tài liệu](../README.md) → [Kiểm chứng](README.md) → **NanoFable 06/10/2026**

## Phạm vi và kết quả timing

Top được kiểm chứng là `llm_soc`, với bốn attention divider lane và bốn sigmoid
lane; performance counters và opcode debug index tắt. Không đổi RTL, LUT,
QSF/QPF/SDC, timing constraints hoặc numeric expectations trong lượt chạy này.

Quartus Prime Lite 25.1std.0 đã hoàn tất synthesis, fit, STA và extraction.
[Timing manifest](timing/nanofable_max_20261006/manifest.json) xác minh cả 41
RTL/LUT assets và cấu hình hiện tại. Fmax thấp nhất là **100,78 MHz**, đạt gate
100 MHz ở cả bốn corner. Các số dưới đây là post-fit FPGA timing của backend
EDA; chưa phải ASIC signoff hay kết quả chạy trên board.

| Corner (1.100 mV) | Restricted Fmax MHz | Setup ns | Hold ns | Recovery ns | Removal ns | Pulse ns |
|---|---:|---:|---:|---:|---:|---:|
| Slow 85 °C | 100,78 | +0,077 | +0,245 | +0,123 | +1,599 | +3,600 |
| Slow 0 °C | 101,50 | +0,148 | +0,232 | +0,332 | +3,666 | +3,548 |
| Fast 85 °C | 148,41 | +3,262 | +0,131 | +4,535 | +2,330 | +3,801 |
| Fast 0 °C | 161,60 | +3,812 | +0,115 | +5,473 | +0,976 | +3,790 |

TNS của mọi check bằng **0**. Cả sáu nhóm unconstrained/illegal clock, input và
output đều có setup/hold count **0**. Worst setup path là
`vector_q[383] → input_cache_q[6][383]`, với data delay 9,627 ns tại Slow 85 °C.
Margin +0,077 ns vẫn nhỏ; thay đổi source hoặc backend cần đo lại.

| Fitted resource | Số lượng |
|---|---:|
| ALMs | 59.605 |
| Registers | 66.924 |
| Block memory bits | 9.516.544 |
| RAM blocks | 1.186 |
| DSP blocks | 0 |
| Pins | 186 |

Synthesis bắt đầu 01:28:33, fit bắt đầu 01:34:09, STA bắt đầu 02:22:37 và
extraction bắt đầu 02:24:35 ngày 06/10/2026 (Asia/Saigon).
[Commands](timing/nanofable_max_20261006/commands.json) giữ timestamp UTC và
arguments thực tế. Assistant chỉ đọc log/report sau khi toàn bộ Quartus flow
kết thúc; trong lúc chạy chỉ theo dõi metadata tiến trình.

## Gate và diagnostics

`FULL_RTL_APPLICATION_GATE_PASS: Fmax=100.78 MHz` được xác nhận trước
export/reference checkpoint. [Unit result](../../tests/full_rtl/unit_results.json)
đủ bảy nhóm PASS: RAM technology, math, RAM, protocol, selection, operators
và autonomous graph. Source, tests, runner và log/binding hashes đều còn khớp.

Synthesis có 0 errors/22 warnings; fitter có 0 errors/4 warnings, gồm một
Critical Warning về pin locations; STA có 0 errors/0 warnings. Diagnostics
được giữ nguyên trong report, không thêm suppression hoặc timing exception.

| Diagnostic | Đánh giá trên lượt hoàn tất này |
|---|---|
| 10036, 10027, 287013, 276020, 13024 | Cùng các loại đã [rà soát từ lượt trước](warning_review_nanofable_20261005.md): state không dùng, index có phạm vi hẹp có chủ ý, vendor RAM inputs, read-during-write forwarding và debug constants. RTL và unit evidence không đổi. |
| 292013 | Giới hạn LogicLock của license Quartus Lite, thuộc backend. |
| 15714, Critical Warning 169085 | Thiếu board I/O/pin locations cho 125 pins. Đây là EDA demonstration; không đặt board pinout giả vào portable RTL. Timing và unconstrained checks vẫn phải PASS. |
| 176251 | Wildcard Fast Output Register cho `pc_debug[*]` và `instr_debug[*]` có một số destination không hợp lệ; các debug bus có bits hằng. Quartus bỏ qua các target đó. Tất cả output timing vẫn được kiểm tra và PASS. Assignment thuộc QSF, không thuộc portable compute/control. |

## Cấu hình demo

Checkpoint là NanoFable-1M-ternary seed1 đã pin; 12 assets đã qua SHA-256 check.
Checkpoint gốc khai báo context **512 token**, còn RTL hiện tại hỗ trợ **128**.
Theo phạm vi được chọn, demo dùng hết context của RTL:

| Tham số | Giá trị |
|---|---|
| Prompt | `Once upon a time` |
| Prompt IDs | 433, 449, 261, 398 |
| Prompt tokens | 4 |
| NewTokens / MinNew | 124 / 124 |
| Tổng context | 128 |
| Temperature | 166 (U8/F8, xấp xỉ 0,6484) |
| Seed | 7 |

`MinNew=124` mask EOS để dùng đủ budget. CPU host nạp parameter/prompt và đọc
kết quả; toàn prefill/decode, attention, head và token selection chạy trên RTL.
Reference số nguyên dùng để so sánh token, không điều khiển DUT.

## Kết quả application

**Đang chạy**, chưa có application PASS cuối cùng. Reference đã chuẩn bị đủ
124 continuation tokens; mô phỏng phải kiểm tra toàn bộ token và provenance
trước khi kết luận. Chất lượng văn bản sẽ được đánh giá sau khi decode token RTL.

Workflow và cấu hình thực thi (`../../tests/full_rtl/evidence/nanofable_max_20261006/workflow.ps1`; historical target unavailable in this checkout)
và trạng thái (`../../tests/full_rtl/evidence/nanofable_max_20261006/status.json`; historical target unavailable in this checkout)
giữ tiến trình của lượt mới. Một worker cũ chỉ đợi manifest đã được dừng để
tránh chạy application song song; trạng thái trước khi dừng được giữ trong
evidence mới. Evidence của các lượt trước không bị reset hoặc ghi đè bởi lượt này.

## Tái tạo

[Hướng dẫn NanoFable](../demos/language.md) có lệnh gate và application.
Workflow của lượt này chạy đúng manifest và sampling config ở trên. Chọn tag
mới cho lần chạy tiếp theo; không ghi đè evidence cũ. Chỉ commit/push kết quả
sau khi application hoàn tất và các checks đạt PASS.
