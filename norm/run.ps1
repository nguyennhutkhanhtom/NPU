param(
    [string]$SimBin='C:\intelFPGA\20.1\modelsim_ase\win32aloem',
    [string]$Python='C:\Users\khanh\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
)
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot
$sim=Join-Path $PSScriptRoot 'sim'
$results=[ordered]@{}
$runLock=$null
function Invoke-NormTest([string]$Top,[string]$Name,[string]$Marker,[string[]]$Overrides=@()) {
    & "$SimBin/vsim.exe" -c -onfinish exit -l "$Name.log" "work.$Top" @Overrides -do 'run -all; quit -f' *> "$Name.console"
    if($LASTEXITCODE -ne 0 -or !(Select-String -LiteralPath "$Name.log" -SimpleMatch $Marker -Quiet) -or
        (Select-String -LiteralPath "$Name.log" -Pattern '^# \*\* (Fatal|Error):' -Quiet)) {
        Get-Content -LiteralPath "$Name.log" -Tail 25
        throw "Test failed: $Name"
    }
    $pass=(Select-String -LiteralPath "$Name.log" -SimpleMatch $Marker | Select-Object -Last 1).Line
    $results[$Name]=[ordered]@{status='PASS';marker=$pass;log="sim/$Name.log"}
    Write-Output $pass
}
New-Item -ItemType Directory -Force $sim | Out-Null
Push-Location $sim
try {
    $runLock=[IO.File]::Open((Join-Path $sim '.run.lock'),'OpenOrCreate','ReadWrite','None')
    & $Python (Join-Path $PSScriptRoot 'generate_tests.py') *> generate.log
    if($LASTEXITCODE -ne 0) {Get-Content generate.log -Tail 15;throw 'NORM fixture/LUT validation failed'}
    New-Item -ItemType Directory -Force data | Out-Null
    Copy-Item -LiteralPath (Join-Path $repo 'data/normContent.mif') -Destination data/normContent.mif
    if(!(Test-Path work)) {
        & "$SimBin/vlib.exe" work *> create.log
        if($LASTEXITCODE -ne 0) {throw 'Cannot create ModelSim library'}
    }
    $rtl=@(Get-ChildItem -LiteralPath (Join-Path $repo 'Verilog Source code') -File | Where-Object {$_.Extension -in '.sv','.v'})
    $tests=@(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'tests') -Filter '*.sv' -File)
    $legacyTest=Join-Path $repo 'tmatmul/sim/tb_core.sv'
    $aluTest=Join-Path $repo 'review/addsub_20260917/tb_rowwise.sv'
    & "$SimBin/vlog.exe" -sv -work work @($rtl.FullName) @($tests.FullName) $legacyTest $aluTest *> compile.log
    if($LASTEXITCODE -ne 0) {Get-Content compile.log -Tail 25;throw 'RTL compile failed'}
    Invoke-NormTest tb_norm_rom rom 'NORM_ROM_PASS'
    Invoke-NormTest tb_norm_unit unit 'NORM_UNIT_PASS'
    Invoke-NormTest tb_norm_core core 'NORM_CORE_PASS'
    Invoke-NormTest tb_norm_core core-tmatmul 'NORM_CORE_PASS' @('-gUSE_TM=1')
    Invoke-NormTest tb_norm_memory memory 'NORM_MEMORY_PASS'
    # Existing TMATMUL acceptance test, using the actual core and arithmetic.
    Invoke-NormTest tb_core legacy-tmatmul 'CORE_PASS'
    Invoke-NormTest tb_rowwise legacy-rowwise 'ROWWISE_PASS'
    & "$SimBin/vsim.exe" -c -onfinish exit -l missing.log work.tb_norm_missing -do 'run -all; quit -f' *> missing.console
    if(!(Select-String -LiteralPath missing.log -SimpleMatch 'Missing NORM square LUT' -Quiet) -or
       (Select-String -LiteralPath missing.log -SimpleMatch 'GUARD_MISSED' -Quiet)) {throw 'Missing LUT guard failed'}
    $results['missing-lut']=[ordered]@{status='PASS';scope='Expected fatal for missing ROM file'}
    Write-Output 'NORM_MISSING_LUT_GUARD_PASS'
    $hashes=[ordered]@{}
    foreach($path in @($rtl.FullName)+@($tests.FullName)+@($legacyTest,$aluTest,$PSCommandPath,
        (Join-Path $PSScriptRoot 'generate_tests.py'),(Join-Path $repo 'python/generate_norm_lut.py'),(Join-Path $repo 'data/normContent.mif'))) {
        $hashes[$path.Substring($repo.Length+1).Replace('\','/')]=(Get-FileHash -LiteralPath $path).Hash.ToLower()
    }
    [ordered]@{status='PASS';utc=[DateTime]::UtcNow.ToString('o');tests=$results;sources=$hashes;
        scope='32-lane Q4.12 RMSNorm, per-word ISA integration, ModelSim RTL simulation';synthesis_run=$false} |
        ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'verification.json') -Encoding utf8
} finally {
    if($null -ne $runLock) {$runLock.Dispose()}
    Pop-Location
}
