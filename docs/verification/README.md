# Kiểm chứng llm_soc

> **Category: GUIDE.**

[Tài liệu](../README.md) → **Kiểm chứng**

Đọc [trạng thái mới nhất](optimization_status.md) trước khi chạy lại. Trang này
hướng dẫn chọn đúng phạm vi: synthetic units/graph, portable elaboration,
full-top timing hoặc application checkpoint.

## Các mức kiểm chứng

| Mức | Entry point | PASS xác nhận điều gì? |
|---|---|---|
| Bảy nhóm tổng hợp | tests/full_rtl/run_units.ps1 | Arithmetic, RAM, protocol, selection, operators và graph khớp fixture/reference |
| Host cancellation | tests/full_rtl/run_host_cancel_100mhz.ps1 | Cancel/commit/ACK contract của cùng RTL |
| Portable elaboration | tests/full_rtl/run_portable_100mhz.ps1 | Full top elaborate với USE_QUARTUS_MEMORY=0 và không binding vendor modules |
| Full-top timing | tools/timing/run.ps1 -Project quartus/llm_soc | Fit và all-corner STA của đúng source/config |
| Pretrained application | tests/full_rtl/run_application.ps1 | Token RTL của checkpoint thật khớp reference integer |
| Chất lượng văn bản | Đọc generated_text.md và đánh giá riêng | Mức mạch lạc/phù hợp của paragraph thực tế |

Sáu nhóm non-graph chỉ có trạng thái `SIX_GROUPS_PASS_GRAPH_PENDING`.
Application gate yêu cầu **cả bảy nhóm**, bao gồm autonomous graph. Portable
elaboration dùng `run 0`; kết quả đó chưa phải ASIC implementation/signoff.

## Chuẩn bị môi trường

Các lệnh dưới đây chạy ở repository root trong PowerShell:

```powershell
Set-Location -LiteralPath 'D:/2151097_Nguyen Nhut Khanh'
$pythonExe = 'C:/Users/khanh/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
$simBin = 'C:/altera_lite/25.1std/questa_fse/win64'
$quartusBin = 'C:/altera_lite/25.1std/quartus/bin64'
```

Dùng tên library và evidence tag mới cho mỗi lượt kiểm chứng. Không compile
lại library đang được một phiên vsim sử dụng. License hiện tại cho phép một
simulation session; Quartus là tiến trình độc lập, nhưng không sửa source/config
khi một build đang đo chúng.

## Chạy bảy nhóm units và graph

RAM helper dùng một timing manifest đã lưu để nhận biết đúng bản Quartus và
RAM model. Ví dụ `opt_fulltop7` bên dưới chỉ dùng cho việc nhận biết model;
application vẫn phải qua gate khớp cấu hình hiện tại.

```powershell
$ramTiming = 'docs/verification/timing/opt_fulltop7/manifest.json'
$ramModel = 'tests/full_rtl/build/questa25_model'
& $pythonExe tests/full_rtl/memory_model.py --timing $ramTiming --sim-bin $simBin --output $ramModel
if ($LASTEXITCODE -ne 0) { throw 'RAM model chưa được xác minh.' }
$unitArgs = @{
    SimBin = $simBin
    Python = $pythonExe
    Questa = $true
    MemoryModelManifest = "$ramModel/manifest.json"
    TimingManifest = $ramTiming
    WorkLibraryName = 'my_units_20261006'
    EvidenceTag = 'my_units_20261006'
}
& tests/full_rtl/run_units.ps1 @unitArgs
```

Result hiện hành nằm ở `tests/full_rtl/unit_results.json`; log, compile list và
binding reports nằm trong build. Archive các kết quả quan trọng bằng
[checkpoint helper](../../tools/optimization/README.md) trước lượt chạy kế tiếp.
Tham số `-UnitsOnly` chỉ chạy sáu nhóm; `-OnlyTop` dùng để debug nhóm chọn riêng.
Chúng không thay cho all-seven PASS khi mở gate.

## Portable elaboration và host probe

Portable elaboration dùng library đã compile đủ RTL; tên ví dụ khớp block trên:

```powershell
& tests/full_rtl/run_portable_100mhz.ps1 -WorkLibraryName my_units_20261006 -EvidenceTag my_portable_20261006
& tests/full_rtl/run_host_cancel_100mhz.ps1 -WorkLibraryName my_host_20261006 -EvidenceTag my_host_20261006
```

Host runner hiện pin tool paths và RAM/timing-model metadata trong script.
Kiểm tra các đường dẫn khi chuyển máy. Mỗi evidence directory giữ source hashes,
commands và diagnostics; không ghi đè một tag đã có.

## Full-top synthesis, fit và timing

Luôn chỉ rõ `-Project quartus/llm_soc`; default của timing runner là project legacy.

```powershell
& tools/timing/run.ps1 -Project quartus/llm_soc -Tag my_timing_20261006 -QuartusBin $quartusBin -Python $pythonExe
```

Sau khi lượt timing hoàn tất, dùng manifest của nó với `check_gate.py`.
[Timing guide](timing/README.md) giải thích Fmax, slack, TNS, unconstrained paths
và những file cần giữ. [NanoFable guide](../demos/language.md) hướng dẫn application.

## Khi nào cần chạy lại?

| Thay đổi | Kiểm chứng bị ảnh hưởng |
|---|---|
| RTL hoặc LUT | Units/graph, portable elaboration khi cần, full-top timing và application |
| Numeric reference hoặc test inputs | Nhóm test liên quan, all-seven evidence trước application |
| QSF/QPF/SDC | Full-top timing với cấu hình mới; unit PASS có thể còn áp dụng nếu RTL/test inputs không đổi |
| Tool/compiler/RAM model | Cache model mới và simulation/binding evidence tương ứng |
| Prompt hoặc sampling config | Lượt application mới sau khi gate còn PASS |
| Nội dung docs/mục lục | Rà văn phong, links và code examples; không suy ra timing hay numerical PASS mới |

Evidence phải khớp raw source hashes, test hashes và log/binding report hashes.
Không nới constraints, numeric expectations hoặc timing exceptions để biến
một kết quả FAIL thành PASS.

## Legacy và lịch sử

[Core matmulfree](../../tests/README.md#regression-legacy) có runner `tests/run.ps1`
và 10 nhóm regression riêng. Các demo MNIST/hybrid thuộc
[demo legacy](../demos/legacy/README.md).
[Lịch sử timing](../history/timing_development.md) và
[lịch sử full graph](../history/full_rtl_development.md) giữ các mốc trước tối ưu.

## Pretrained application gate

Before exporter/reference inference and application simulation, `check_gate.py` requires matching source/configuration/report hashes, all seven unit/graph groups, all-corner post-fit Fmax ≥100 MHz, nonnegative setup/hold/recovery/removal/pulse slack, zero TNS and unconstrained paths, and zero fitted DSP/PLL/DLL/HSSI resources. Keep the 100 MHz constraints even when reporting a failing result. See [language execution](../demos/language.md).
