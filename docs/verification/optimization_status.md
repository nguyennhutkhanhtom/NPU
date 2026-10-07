# Trạng thái kiểm chứng

[Tài liệu](../README.md) → [Kiểm chứng](README.md) → **Trạng thái**

Cập nhật ngày **06/10/2026**, múi giờ Asia/Saigon. Đây là trang tra cứu trạng thái;
manifest, source hashes và log là bằng chứng gốc.

## Bản RTL và cấu hình hiện tại

| Mục | Kết quả ghi nhận | Phạm vi áp dụng |
|---|---|---|
| Bảy nhóm regression | [opt_final4: PASS](../../tests/full_rtl/evidence/opt_final4_all/results.json), 0 compile/runtime warnings | Cả 41 RTL/LUT assets vẫn khớp workspace |
| Graph tổng hợp | 1.066.965 compute clocks; 2 prompt token, 3 token mới, 16 lượt transformer layer | Fixture tổng hợp, giữ các numeric/token/causal/traffic checks |
| Host cancellation | [opt_host1: PASS](../../tests/full_rtl/evidence/opt_host1/results.json) | Cùng RTL; accepted write và ACK sau commit |
| Portable elaboration | [opt_final4: PASS](portable_elaboration_opt_final4/results.json) | Cùng RTL; USE_QUARTUS_MEMORY=0, 0 errors/warnings |
| Timing đã hoàn tất | [nanofable_max_20261006: PASS](timing/nanofable_max_20261006/manifest.json), minimum Fmax 100,78 MHz | Khớp toàn bộ RTL/QSF/QPF/SDC hiện tại; cả bốn corner đạt gate |
| Application pretrained | [Trạng thái workflow](../../tests/full_rtl/evidence/nanofable_max_20261006/status.json): APPLICATION_RUNNING | Gate PASS; đang chạy 4 prompt token + 124 token mới, context RTL 128 |

Lượt `nanofable_max_20261006` đã đo lại cấu hình có metadata version/partition
hiện tại và thu được cùng Fmax, slack và resources với `opt_fulltop7`.
Gate đã xác minh source/config, report hashes và all-seven unit evidence;
export/reference checkpoint chỉ bắt đầu sau bước đó. Không sửa hash, constraints
hay ngưỡng kiểm tra để bỏ qua điều kiện này. Trạng thái workflow là lần ghi cuối
của script; kiểm tra process để biết tiến trình còn chạy hay đã kết thúc.

## Số liệu của checkpoint tối ưu

Các con số sau thuộc `opt_final4` và `opt_fulltop7`, với mặc định bốn divider,
bốn sigmoid lane, performance counters và opcode debug index tắt.

| Chỉ tiêu | Baseline task-start | Checkpoint tối ưu |
|---|---:|---:|
| Graph compute clocks | 4.254.046 | 1.066.965 |
| Minimum Fmax | 98,39 MHz | 100,78 MHz |
| Worst setup slack | -0,164 ns | +0,077 ns |
| ALMs | 53.974 | 59.605 |
| Registers | 55.466 | 66.924 |
| RAM blocks | 1.186 | 1.186 |
| DSP blocks | 0 | 0 |

Graph dùng ít hơn **74,92% compute clocks**, tương đương **3,987 lần** theo cùng
benchmark. Đây là số chu kỳ tính toán, không phải thời gian mô phỏng trên PC.
TNS của mọi check ở bốn corner trong `opt_fulltop7` bằng 0; không có path
unconstrained. Worst hold là +0,115 ns. Margin setup +0,077 ns cần được kiểm tra
lại khi RTL hoặc backend thay đổi.

Traffic graph đã kiểm tra: 77.756 parameter reads, 1.828 vector reads,
1.564 vector writes, 320 KV reads và 128 KV writes.
Tỷ lệ thay đổi RTL của task tối ưu là `(828 + 265) / 5.165 × 100 = 21,16%`;
không tính comments, dòng trống, tests, docs và thay đổi có sẵn trước task.

## Điều kiện chạy model thật

Trước export/reference inference và mô phỏng application, runner kiểm tra:

1. Cả bảy nhóm unit/graph PASS, khớp RTL, test inputs và log/binding evidence.
2. Full-top llm_soc post-fit đạt ít nhất 100 MHz ở cả bốn corner.
3. Setup, hold, recovery, removal và pulse slack không âm; TNS = 0.
4. Không có unconstrained path/clock/port; report và source/config hashes khớp.
5. Fitted DSP, PLL, DLL và HSSI resources bằng 0 theo gate hiện tại.

[Lệnh kiểm tra gate và chạy demo](../demos/language.md) có hướng dẫn đầy đủ.
[Hướng dẫn tái kiểm chứng](README.md) ghi khi nào cần chạy lại units hoặc timing.
Chỉ một phiên mô phỏng Questa chạy tại một thời điểm trên license đang dùng.

## Evidence và tài liệu liên quan

- [Implementation review version 3](../reviews/rtl_change_review_v3.md)
- [Hợp đồng cache và streaming](../design/exact_throughput_optimization.md)
- [Timing: cách đọc report](timing/README.md)
- [Rà soát warnings của lượt NanoFable](warning_review_nanofable_20261005.md)
- [Baseline source giữ nguyên](optimization_baseline/rtl/)

Các checkpoint fail, canceled và intermediate vẫn được lưu trong evidence.
Chúng phục vụ truy vết; chỉ kết quả hoàn tất và khớp source/config mới có thể
mở gate application. Quartus là backend EDA, chưa phải ASIC signoff.
