# Chạy NanoFable thật trên llm_soc

> Branch `remote`: các lệnh local trong tài liệu này là lịch sử. Chạy checkpoint bằng [flow server](../../tools/server/README.md#application-checkpoint); không dùng hardware gate FPGA cũ cho cấu hình mới.


> **Category: GUIDE.**

[Tài liệu](../README.md) → [Demo](README.md) → **NanoFable**

Runner dùng checkpoint **NanoFable-1M-ternary seed1** đã pin. Host nạp parameters,
prompt và cấu hình; toàn bộ prefill/decode, attention, head và token selection chạy
trong mô phỏng RTL. Reference số nguyên trên CPU dùng để kiểm tra token kết quả.

## Trước khi chạy

| Cần có | Giá trị đang dùng trên workspace này |
|---|---|
| Top | llm_soc; không chọn matmulfree cho application này |
| Python | 3.11 hoặc 3.12 cho packages đã pin |
| Simulator | Questa Altera Starter 2025.2, trong C:/altera_lite/25.1std/questa_fse/win64 |
| RAM model | altera_mf.v của bản Quartus được timing manifest ghi nhận |
| Checkpoint/tokenizer | tests/language_demo/upstream, SHA-256 khớp upstream_manifest.json |
| Evidence | Cả bảy nhóm PASS và full-top all-corner timing đạt ≥100 MHz, đúng RTL/config |

Trạng thái verification và application hiện tại: [optimization status](../verification/optimization_status.md). Mỗi lần chỉ dùng một Questa session vì application dùng chung tên build.

## Các bước chạy

### 1. Mở PowerShell ở repository

```powershell
Set-Location -LiteralPath 'D:/2151097_Nguyen Nhut Khanh'
$pythonExe = 'C:/Users/khanh/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
$simBin = 'C:/altera_lite/25.1std/questa_fse/win64'
& $pythonExe --version
```

Các đường dẫn trên trỏ đến runtime và tool đang dùng trong workspace. Khi đổi máy,
hãy thay bằng installation tương ứng. `setup.ps1` yêu cầu Python 3.11/3.12.

### 2. Chuẩn bị checkpoint và dependencies

Nếu assets đã có, chỉ cần kiểm tra file:

```powershell
& $pythonExe tests/language_demo/fetch_assets.py --check
```

Nếu thiếu assets hoặc packages, chạy setup một lần:

```powershell
& tests/language_demo/setup.ps1 -Python $pythonExe
```

Setup cài NumPy, safetensors và tokenizers vào thư mục packages riêng, rồi tải
và kiểm tra 12 file đã pin. Bước này chưa thực thi checkpoint inference.

### 3. Chọn manifest đúng và kiểm tra gate

Chỉ chọn file `manifest.json` của một lượt timing đã hoàn tất. Manifest dưới đây
là ví dụ lịch sử; chọn manifest áp dụng từ trang trạng thái và kiểm tra gate trước khi chạy.

```powershell
$timingManifest = 'docs/verification/timing/nanofable_max_20261006/manifest.json'
if (-not (Test-Path -LiteralPath $timingManifest)) {
    throw 'Timing chưa hoàn tất. Xem status/log của workflow hoặc tạo lượt timing mới.'
}
& $pythonExe tests/full_rtl/check_gate.py $timingManifest
if ($LASTEXITCODE -ne 0) { throw 'Gate chưa PASS; dừng trước export và application.' }
```

Kết quả cần thấy: `FULL_RTL_APPLICATION_GATE_PASS`. Nếu source, tests, evidence
logs hoặc QSF/QPF/SDC không khớp, xem [cách tái kiểm chứng](../verification/README.md).
Không đổi hash, giới hạn timing hay expected tokens để vượt gate.

### 4. Chạy thử ngắn: 8 token greedy

```powershell
$appArgs = @{
    TimingManifest = $timingManifest
    Python = $pythonExe
    SimBin = $simBin
    Prompt = 'Once upon a time'
    NewTokens = 8
    MinNew = 8
    Temperature = 0
    Seed = 7
}
& tests/full_rtl/run_application.ps1 @appArgs
```

Runner kiểm tra gate, chuẩn bị RAM model, export parameter image và reference,
compile testbench, mô phỏng rồi xác minh evidence. `MinNew=8` mask EOS trong
8 token; `Temperature=0` dùng greedy. Bắt đầu với lượt ngắn để biết pipeline
application hoạt động trước khi chọn continuation dài.

Để chạy thử chức năng khi RTL đã đổi hoặc timing/unit gate chưa PASS, bỏ qua
bước gọi `check_gate.py` ở trên và dùng:

```powershell
& tests/full_rtl/run_application.ps1 @appArgs -SkipGate
```

Chế độ này vẫn cần `TimingManifest` để chọn RAM model của Quartus và vẫn
kiểm tra token RTL khớp reference. Kết quả được lưu riêng trong
`tests/full_rtl/application_functional_results.json` (`hardware_gate: SKIPPED`)
và `tests/full_rtl/generated_functional_text.md`; không chứng minh timing hay
bảy nhóm unit đã PASS cho RTL hiện tại.

### 5. Chạy continuation dài hơn

Sau khi đã lưu kết quả lượt trước, thay các tham số trong cùng PowerShell:

```powershell
$appArgs.Prompt = 'Once upon a time, Lily found a tiny kitten.'
$appArgs.NewTokens = 96
$appArgs.MinNew = 64
$appArgs.Temperature = 166
& tests/full_rtl/run_application.ps1 @appArgs
```

Temperature dùng định dạng raw U8/F8: 166 tương đương khoảng 0,6484. EOS có thể kết thúc
sau `MinNew`; không phải lần nào cũng sinh đủ `NewTokens`. Exporter kiểm tra
`prompt token count + NewTokens ≤128`; số token của prompt không phải số từ.
Chọn prompt tiếng Anh ngắn cho checkpoint kể chuyện này. Độ dài mô phỏng trên PC
phụ thuộc prompt/context và số token, khác với thời gian tính theo clock phần cứng.

### 6. Dùng hết context của RTL hiện tại

Checkpoint gốc khai báo context **512 token** trong `upstream/config.json`.
RTL hiện tại hỗ trợ **128 token**, tính cả prompt và continuation. Vì vậy,
demo tối đa của bản RTL này dùng prompt `Once upon a time` (4 token) và sinh
124 token mới; đây là giới hạn của RTL đang kiểm chứng.

```powershell
$appArgs.Prompt = 'Once upon a time'
$appArgs.NewTokens = 124
$appArgs.MinNew = 124
$appArgs.Temperature = 166
$appArgs.Seed = 7
& tests/full_rtl/run_application.ps1 @appArgs
```

`MinNew=124` giữ EOS bị mask trong toàn bộ continuation để dùng đủ 128 vị trí.
Đây là cấu hình sampling; token kết quả vẫn phải khớp reference số nguyên.
Muốn dùng đủ context 512 của checkpoint cần mở rộng RTL, memory/address geometry,
exporter và testbench, rồi chạy lại các gate trước application.

## Đọc tiến độ và kết quả

Mở terminal thứ hai ở repository nếu muốn xem log trong lúc mô phỏng:

```powershell
Get-Content -LiteralPath 'tests/full_rtl/build/application.log' -Tail 20 -Wait
```

Ctrl+C trong terminal theo dõi chỉ dừng `Get-Content`; để dừng mô phỏng, dùng
terminal đang chạy runner. Log báo `FULL_RTL_LOAD_PROGRESS` mỗi 1.024 parameter
rows trong lúc nạp checkpoint, rồi `FULL_RTL_GRAPH_START` khi bắt đầu inference.
Log báo `FULL_RTL_PROGRESS` mỗi 100.000 compute clocks và
`FULL_RTL_TOKEN_VERIFIED` cho từng token được so sánh. Runner dừng ngay khi mismatch.

| File | Nội dung |
|---|---|
| tests/full_rtl/generated_text.md | Continuation decode từ token RTL thực tế |
| tests/full_rtl/application_results.json | PASS, token IDs, RTL text, source/evidence hashes và text_quality |
| tests/full_rtl/build/rtl_tokens.txt | Token IDs host đọc từ output window |
| tests/full_rtl/build/application.log | Runtime log và FULL_RTL_APPLICATION_PASS |
| tests/full_rtl/build/application_compile.log | Compile diagnostics |
| tests/full_rtl/build/reference.json | Input config và continuation kỳ vọng của reference integer |

Một lượt hoàn tất cần `FULL_RTL_APPLICATION_PASS` và
`FULL_RTL_APPLICATION_EVIDENCE_PASS`. `application_results.json` ghi `status=PASS`
khi token RTL khớp reference. Mục `text_quality=NOT_ASSESSED` cần được bổ sung
bằng cách đọc paragraph thực tế; PASS numeric chưa xác nhận chất lượng văn bản.

## Lưu kết quả trước lượt kế tiếp

Runner hiện dùng chung thư mục build và output file cho các lượt application.
Trước khi chạy lại, lưu một archive mới, ví dụ:

```powershell
$appArchive = 'tests/full_rtl/evidence/my_nanofable_20261006'
if (Test-Path -LiteralPath $appArchive) { throw 'Chọn một tên archive chưa có.' }
New-Item -ItemType Directory -Path $appArchive | Out-Null
Copy-Item -LiteralPath 'tests/full_rtl/application_results.json','tests/full_rtl/generated_text.md' -Destination $appArchive
$appFiles = @('application_compile.log','application_compile.console','application.log',
    'application.log.console','reference.json','rtl_tokens.txt','application_design_units.json',
    'parameter.mem','prompt.mem','expected.mem','config.svh','application_sources.f')
foreach ($name in $appFiles) {
    Copy-Item -LiteralPath (Join-Path 'tests/full_rtl/build' $name) -Destination $appArchive
}
$hashes = [ordered]@{}
Get-ChildItem -LiteralPath $appArchive -File | ForEach-Object {
    $hashes[$_.Name] = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
}
$hashes | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $appArchive 'sha256.json') -Encoding utf8
```

Archive này lưu kết quả/log/input, còn timing và source snapshot được tham chiếu qua
manifest. Giữ cả RAM-model cache được application result tham chiếu. Không sửa
archive cũ để biểu diễn một lần chạy khác.

## Khi runner dừng

| Thông báo / tình huống | Cách xử lý |
|---|---|
| Missing manifest hoặc Configuration changed after timing | Chờ/tạo full-top timing cho cấu hình hiện tại rồi kiểm tra gate |
| RTL changed hoặc unit evidence stale | Chạy lại đúng unit/graph hoặc timing bị ảnh hưởng; giữ evidence cũ |
| Missing pinned asset / import error | Chạy setup với Python 3.11/3.12 hoặc kiểm tra lại assets/packages |
| License unavailable | Kết thúc phiên Questa đang dùng license trước khi mở phiên mới |
| Prompt vượt context | Giảm prompt hoặc NewTokens; giữ tổng token ≤128 |
| Token mismatch, timeout hoặc error | Giữ log/input/reference để debug; không đổi expected IDs hay watchdog để nhận PASS |

[Host map](../design/host_interface.md) giải thích những gì testbench ghi vào DUT.
[Báo cáo hybrid cũ](legacy/nanofable_hybrid.md) ghi CPU generation và linear-only
RTL trước đây; kết quả đó thuộc một flow khác với application này.
