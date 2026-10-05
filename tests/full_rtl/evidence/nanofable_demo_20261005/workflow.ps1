$ErrorActionPreference='Stop'
$repo='D:/2151097_Nguyen Nhut Khanh'
$python='C:/Users/khanh/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
$timing='docs/verification/timing/nanofable_demo_20261005_retry1'
$evidence=$PSScriptRoot
Set-Location -LiteralPath $repo
function Save-Status([string]$Stage,[string]$Message) {
    [ordered]@{stage=$Stage;message=$Message;updated_utc=[DateTime]::UtcNow.ToString('o');timing_manifest="$timing/manifest.json";prompt='Once upon a time, Lily found a tiny kitten.';max_new_tokens=96;seed=7} |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $evidence 'status.json') -Encoding utf8
    Write-Output "$Stage`: $Message"
}
try {
    Save-Status 'WAITING_FOR_TIMING' 'Awaiting the fresh full-top synthesis, fit and all-corner STA run.'
    $deadline=[DateTime]::UtcNow.AddHours(4)
    while(!(Test-Path -LiteralPath "$timing/manifest.json")) {
        foreach($stage in @('map','fit','sta','extract')) {
            $stageLog="$timing/$stage.log"
            if((Test-Path -LiteralPath $stageLog) -and (Select-String -LiteralPath $stageLog -Pattern 'was unsuccessful|Internal Error:|^Error:' -Quiet)) {
                throw "Timing stage failed: $stage; inspect $stageLog"
            }
        }
        if([DateTime]::UtcNow -gt $deadline) {throw 'Timing manifest did not become available within four hours.'}
        Start-Sleep -Seconds 15
    }
    & $python tests/full_rtl/check_gate.py "$timing/manifest.json"
    if($LASTEXITCODE -ne 0) {throw 'Exact-current application gate failed. No checkpoint inference launched.'}
    Save-Status 'APPLICATION_RUNNING' 'Gate PASS; executing pretrained NanoFable on the full RTL graph.'
    & tests/full_rtl/run_application.ps1 -TimingManifest "$timing/manifest.json" -MemoryModelDir tests/full_rtl/build/nanofable_demo_20261005_memory_model
    if($LASTEXITCODE -ne 0) {throw 'Application runner returned an error.'}
    foreach($name in @('application_results.json','generated_text.md')) {
        Copy-Item -LiteralPath "tests/full_rtl/$name" -Destination (Join-Path $evidence $name) -ErrorAction Stop
    }
    foreach($name in @('application_compile.log','application.log','reference.json','rtl_tokens.txt','application_design_units.json','config.svh','parameter.mem','prompt.mem','expected.mem')) {
        Copy-Item -LiteralPath "tests/full_rtl/build/$name" -Destination (Join-Path $evidence $name) -ErrorAction Stop
    }
    $hashes=[ordered]@{}
    Get-ChildItem -LiteralPath $evidence -File | Where-Object {$_.Name -notin @('status.json','workflow.log','sha256.json')} | ForEach-Object {
        $hashes[$_.Name]=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    $hashes | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $evidence 'sha256.json') -Encoding utf8
    Save-Status 'PASS' 'RTL/reference tokens match; actual decoded text and evidence archived. Text quality requires separate review.'
} catch {
    Save-Status 'FAILED' $_.Exception.Message
    foreach($name in @('application_compile.log','application.log','reference.json','rtl_tokens.txt','application_design_units.json')) {
        $source="tests/full_rtl/build/$name"
        if(Test-Path -LiteralPath $source) {Copy-Item -LiteralPath $source -Destination (Join-Path $evidence $name)}
    }
    throw
}
