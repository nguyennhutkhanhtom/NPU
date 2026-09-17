param([string]$SimBin='C:\intelFPGA\20.1\modelsim_ase\win32aloem')
$ErrorActionPreference='Stop'
$repo=Split-Path (Split-Path $PSScriptRoot)
$sim=Join-Path $PSScriptRoot 'sim'
$rtl=Join-Path $repo 'Verilog Source code'
$baseline=Join-Path $repo 'scale/baseline'
$results=[ordered]@{}
$runLock=$null

function Invoke-Simulation([string]$Library,[string]$Top,[string]$Name,[string]$Marker,[string[]]$Overrides=@()) {
    $log=Join-Path $sim "$Name.log"
    & "$SimBin/vsim.exe" -c -onfinish exit -l $log "$Library.$Top" @Overrides -do 'run -all; quit -f' *> "$log.console"
    if($LASTEXITCODE -ne 0 -or !(Select-String -LiteralPath $log -SimpleMatch $Marker -Quiet) -or
       (Select-String -LiteralPath $log -Pattern '^# \*\* (Fatal|Error):' -Quiet)) {
        Get-Content -LiteralPath $log -Tail 20
        throw "Simulation failed: $Name"
    }
    $pass=(Select-String -LiteralPath $log -SimpleMatch $Marker | Select-Object -Last 1).Line
    $results[$Name]=[ordered]@{status='PASS';marker=$pass;log="sim/$Name.log"}
    Write-Output $pass
}

New-Item -ItemType Directory -Force $sim | Out-Null
Push-Location $sim
try {
    $runLock=[IO.File]::Open((Join-Path $sim '.run.lock'),'OpenOrCreate','ReadWrite','None')
    # Structural fixtures only. No numeric accuracy claim for EXP or SIG.
    [IO.File]::WriteAllLines((Join-Path $sim 'sigContent.mif'),[string[]](@('0000000000000000')*65536))
    [IO.File]::WriteAllLines((Join-Path $sim 'exp_content.mif'),[string[]](@('0000')*512))
    [IO.File]::WriteAllLines((Join-Path $sim 'mem_init.mem'),[string[]](@('00000000000000000000000000000000')*8192))
    $allSources=@(Get-ChildItem -LiteralPath $rtl -File | Where-Object {$_.Extension -in '.v','.sv'})
    $oldSources=@(Get-ChildItem -LiteralPath $baseline -File | Where-Object {$_.Extension -in '.v','.sv'})
    $tests=@(Get-ChildItem -LiteralPath $PSScriptRoot -Filter 'tb_*.sv' -File)
    $evidence=@((Join-Path $repo 'review/sim/tb_review.sv'),
                (Join-Path $repo 'review/audit_20260916/tb_extended.sv'),
                (Join-Path $repo 'review/audit_20260916/tb_param_probe.sv'))
    foreach($lib in @('before_lib','after_lib')) {
        if(!(Test-Path -LiteralPath $lib)) {
            & "$SimBin/vlib.exe" $lib *> "$lib-create.log"
            if($LASTEXITCODE -ne 0) {throw "Cannot create $lib"}
        }
    }
    & "$SimBin/vlog.exe" -sv -work before_lib ("+incdir+"+(Join-Path $repo 'review/sim')) @($oldSources.FullName) (Join-Path $PSScriptRoot 'tb_reproduce.sv') @evidence *> compile-before.log
    if($LASTEXITCODE -ne 0) {Get-Content compile-before.log -Tail 20; throw 'Baseline compilation failed'}
    & "$SimBin/vlog.exe" -sv -work after_lib @($allSources.FullName) @($tests.FullName) (Join-Path $repo 'review/audit_20260916/tb_param_probe.sv') *> compile-after.log
    if($LASTEXITCODE -ne 0) {Get-Content compile-after.log -Tail 20; throw 'Current RTL compilation failed'}
    Invoke-Simulation 'before_lib' 'tb_reproduce' 'before-reproduce' 'REPRO_PASS EXPECT_BUGS=1 bugs=4' @('-gEXPECT_BUGS=1')
    Invoke-Simulation 'before_lib' 'tb_review' 'baseline-review' 'EVIDENCE_SUMMARY reproduced=17 checks=17'
    Invoke-Simulation 'before_lib' 'tb_extended' 'baseline-extended' 'EXTENDED_SUMMARY reproduced=20 checks=20'
    Invoke-Simulation 'after_lib' 'tb_reproduce' 'after-reproduce' 'REPRO_PASS EXPECT_BUGS=0 bugs=0'
    foreach($width in @(1,4,8,16,32,64)) {
        Invoke-Simulation 'after_lib' 'tb_addsub' "addsub-$width" "ADDSUB_PASS W=$width " @("-gW=$width")
    }
    Invoke-Simulation 'after_lib' 'tb_rowwise' 'rowwise-16' 'ROWWISE_PASS'
    # A deliberate negative elaboration probe documents the remaining scope.
    & "$SimBin/vsim.exe" -c -onfinish exit -l scaled-rowwise-probe.log 'after_lib.tb_param_probe' -do 'run -all; quit -f' *> scaled-rowwise-probe.log.console
    if(!(Select-String -LiteralPath scaled-rowwise-probe.log -Pattern 'vsim-3906' -Quiet) -or
       !(Select-String -LiteralPath scaled-rowwise-probe.log -Pattern 'Error loading design' -Quiet)) {
        throw 'Expected legacy MUL/DIV array-width incompatibility was not observed'
    }
    $results['scaled-rowwise-probe']=[ordered]@{status='EXPECTED_FAILURE';reason='Legacy MUL/DIV unpacked array ports remain 16-bit';log='sim/scaled-rowwise-probe.log'}
    Write-Output 'EXPECTED_FAILURE: full rowwise DATA_WIDTH=8 still requires MUL/DIV parameterization.'
    $sources=[ordered]@{}
    foreach($path in @($allSources.FullName)+@($tests.FullName)+$evidence+@($PSCommandPath)) {
        $sources[$path.Substring($repo.Length+1).Replace('\','/')]=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLower()
    }
    $report=[ordered]@{scope='ADD/SUB wrap, unsigned carry/borrow, signed overflow; full source review';
        status='PASS_WITH_KNOWN_DESIGN_BUGS';generated_utc=[DateTime]::UtcNow.ToString('o');
        tests=$results;sources=$sources;full_scaled_core_verified=$false}
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'verification.json') -Encoding utf8
} finally {
    if($null -ne $runLock) {$runLock.Dispose()}
    Pop-Location
}
