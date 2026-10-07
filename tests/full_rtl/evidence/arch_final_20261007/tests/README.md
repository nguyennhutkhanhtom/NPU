# Testbench và runner cho llm_soc

[Tài liệu](../../docs/README.md) → [Kiểm chứng](../../docs/verification/README.md) → **Full RTL tests**

Các file trong thư mục này compile source tại Verilog Source code.
[Xem trạng thái](../../docs/verification/optimization_status.md) trước khi tái chạy;
[lệnh đầy đủ](../../docs/verification/README.md) nằm ở verification guide.

## Chọn runner

| Runner | Công việc | Output chính |
|---|---|---|
| run_units.ps1 | Bảy nhóm synthetic units/graph; có chọn nhóm để debug | unit_results.json và build logs/binding reports |
| run_host_cancel_100mhz.ps1 | Host cancel/commit/ACK probe | evidence/TAG/results.json |
| run_portable_100mhz.ps1 | run 0 với vendor-free full top | docs/verification/TAG/results.json |
| run_application.ps1 | Checkpoint export/reference và toàn graph application | application_results.json, generated_text.md |
| check_gate.py | Kiểm tra source/test/log/config/report và hardware gates | FULL_RTL_APPLICATION_GATE_PASS hoặc assertion |
| memory_model.py | Compile/verify actual Quartus RAM simulation library | RAM-model manifest |

## Bảy nhóm tổng hợp

| Testbench | Phạm vi |
|---|---|
| tb_memory_ip.sv / tb_quartus_memory | Hai memory backends, OLD_DATA, tile boundaries, sustained requests và reset |
| tb_math.sv / tb_llm_math | Legacy/streaming SIMD, tables, structural arithmetic, ternary và normalization |
| tb_ram.sv / tb_llm_ram | Adapter latency, lane mask, queued writes và reset cancellation |
| tb_protocol.sv / tb_llm_protocol | Host requests, writes, cancellations, bounds và token pipeline |
| tb_selection.sv / tb_llm_selection | Excluded IDs, signed minimum và stable ties |
| tb_operators.sv / tb_llm_operators | Numeric operators, context boundaries, saturation và reset/cancel |
| tb_graph.sv / tb_llm_graph | Host-loaded synthetic graph, phases, token outputs, causality và traffic |

`-UnitsOnly` chạy sáu nhóm non-graph, còn `-OnlyTop` chọn nhóm cụ thể.
Chỉ default all-seven PASS dùng được trong application gate. Các fixture
synthetic xác minh behavior; model thật dùng runner application riêng.

## Cách application hoạt động

1. check_gate.py xác minh đúng full top, sources, tests và post-fit timing.
2. memory_model.py chuẩn bị/kiểm tra actual altera_mf RAM library.
3. export_checkpoint.py tạo parameter.mem, prompt.mem, expected.mem, config.svh
   và reference.json từ checkpoint đã pin.
4. application_tb.sv ghi parameters/prompt/config qua host; RTL tự chạy graph.
5. Monitor chỉ đọc token RTL để so sánh expected IDs. Host reads cuối lượt
   kiểm tra lại returned tokens và ghi rtl_tokens.txt.
6. finalize_application.py kiểm tra input/source/log/binding hashes rồi ghi
   application_results.json và generated_text.md.

Expected IDs không điều khiển DUT. CPU reference tính toán để kiểm chứng;
DUT nhận checkpoint words, prompt và generation configuration.
[Hướng dẫn NanoFable](../../docs/demos/language.md) có lệnh chạy ngắn, chạy dài,
archive kết quả và cách xử lý khi gate từ chối.

## Library, license và evidence

License Questa hiện tại cho phép một simulation session. Dùng WorkLibraryName
và EvidenceTag mới khi chạy units/probes; không overwrite library đang dùng.
Application runner có tên build/output cố định, nên archive trước lượt kế tiếp.

Actual RAM bindings được xác nhận bằng design-unit report, source/compiler/object
hashes và simulation logs. Các library/vendor sources nằm trong ignored cache,
không đưa vào source RTL. Đổi tool/model cần cache mới và evidence tương ứng.

## Interface và lịch sử

[Host map](../../docs/design/host_interface.md) là trang chính cho registers,
handshake, reset và transaction sequence. Các fixed-point contracts nằm ở
[kiến trúc](../../docs/design/full_rtl_language.md).

[Narrative runner cũ](../../docs/history/full_rtl_verification_development.md)
giữ các mốc compile/license/memory/pipeline và canceled attempts. Các log/result
archives dưới evidence giữ nguyên byte và phạm vi của chúng.
