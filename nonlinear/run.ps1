param([string]$SimBin='C:\intelFPGA\20.1\modelsim_ase\win32aloem',
      [string]$Python='C:\Users\khanh\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
$sim=Join-Path $PSScriptRoot 'sim'
$results=[ordered]@{}
$lock=$null
Push-Location $root
try {
    $lock=[IO.File]::Open((Join-Path $sim '.run.lock'),'OpenOrCreate','ReadWrite','None')
    & $Python nonlinear/tools/generate.py *> nonlinear/sim/generate.log
    if($LASTEXITCODE -ne 0) {throw 'LUT generation failed'}
    if(!(Test-Path nonlinear/sim/work)) {& "$SimBin/vlib.exe" nonlinear/sim/work *> nonlinear/sim/vlib.log}
    $rtl=@(Get-ChildItem -LiteralPath 'Verilog Source code' -File | Where-Object {$_.Extension -in '.sv','.v'})
    $tests=@(Get-ChildItem -LiteralPath $sim -Filter 'tb_*.sv' -File)
    & "$SimBin/vlog.exe" -sv -work nonlinear/sim/work @($rtl.FullName) @($tests.FullName) *> nonlinear/sim/compile.log
    if($LASTEXITCODE -ne 0) {Get-Content nonlinear/sim/compile.log -Tail 25;throw 'Compilation failed'}
    function Sim([string]$Test,[string]$Name,[string]$Marker,[string[]]$Overrides) {
        $log=Join-Path $sim "$Name.log"
        & "$SimBin/vsim.exe" -c -onfinish exit -l $log "nonlinear/sim/work.$Test" @Overrides -do 'run -all; quit -f' *> "$log.console"
        if($LASTEXITCODE -ne 0 -or !(Select-String -LiteralPath $log -SimpleMatch $Marker -Quiet) -or
           (Select-String -LiteralPath $log -Pattern '^# \*\* (Fatal|Error):' -Quiet)) {
            Get-Content -LiteralPath $log -Tail 18;throw "Failed $Name"
        }
        $line=(Select-String -LiteralPath $log -SimpleMatch $Marker | Select-Object -Last 1).Line
        $results[$Name]=@{status='PASS';marker=$line};Write-Output $line
    }
    foreach($w in @(8,16)) {
        $addresses=if($w -eq 8) {@(6,7,8)} else {@(7,8,9,10)}
        foreach($a in $addresses) {Sim 'tb_exp' "exp-$w-$a" 'EXP_PASS' @("-gW=$w","-gA=$a")}
        Sim 'tb_norm' "norm-$w" 'NORM_PASS' @("-gW=$w")
        Sim 'tb_dispatch' "dispatch-$w" 'DISPATCH_PASS' @("-gW=$w")
    }
    # Test the actual core control and register wiring. Only unrelated TMATMUL
    # is replaced, with a model that fatals if it is ever enabled.
    $coreDir=Join-Path $sim 'core'
    New-Item -ItemType Directory -Force $coreDir | Out-Null
    if(!(Test-Path nonlinear/sim/core_lib)) {& "$SimBin/vlib.exe" nonlinear/sim/core_lib *> nonlinear/sim/core-vlib.log}
    $coreSources=@($rtl | Where-Object {$_.Name -ne 'ternary_mul.sv'})
    & "$SimBin/vlog.exe" -sv -work nonlinear/sim/core_lib @($coreSources.FullName) nonlinear/sim/models/ternary_inactive.sv nonlinear/sim/tb_core_nonlinear.sv *> nonlinear/sim/core-compile.log
    if($LASTEXITCODE -ne 0) {Get-Content nonlinear/sim/core-compile.log -Tail 15;throw 'Core test compile failed'}
    [IO.File]::WriteAllLines((Join-Path $coreDir 'instruction.mem'),[string[]](@('1111111111111')*512))
    [IO.File]::WriteAllLines((Join-Path $coreDir 'mem_init.mem'),[string[]](@('0')*524288))
    [IO.File]::WriteAllLines((Join-Path $coreDir 'sigContent.mif'),[string[]](@('0000000000000000')*65536))
    Push-Location $coreDir
    try {
        $coreLog=Join-Path $sim 'core-nonlinear.log'
        & "$SimBin/vsim.exe" -c -onfinish exit -l $coreLog '../core_lib.tb_core_nonlinear' -do 'run -all; quit -f' *> "$coreLog.console"
        if($LASTEXITCODE -ne 0 -or !(Select-String -LiteralPath $coreLog -SimpleMatch 'CORE_NONLINEAR_PASS' -Quiet) -or
          (Select-String -LiteralPath $coreLog -Pattern '^# \*\* (Fatal|Error):' -Quiet)) {
            Get-Content -LiteralPath $coreLog -Tail 20;throw 'Core nonlinear integration failed'
        }
        $line=(Select-String -LiteralPath $coreLog -SimpleMatch 'CORE_NONLINEAR_PASS').Line
        $results['core-nonlinear']=@{status='PASS';marker=$line;scope='Actual core with TMATMUL inactive stub'};Write-Output $line
    } finally {Pop-Location}
    $sources=[ordered]@{}
    foreach($f in @($rtl.FullName)+@($tests.FullName)+@($PSCommandPath,(Join-Path $PSScriptRoot 'tools/generate.py'),(Join-Path $sim 'models/ternary_inactive.sv'))) {
        $sources[$f.Substring($root.Length+1).Replace('\','/')]=(Get-FileHash -LiteralPath $f).Hash.ToLower()
    }
    @{status='PASS';tests=$results;sources=$sources;genus_synthesis_run=$false;utc=[DateTime]::UtcNow.ToString('o')} |
       ConvertTo-Json -Depth 8 | Set-Content -Encoding utf8 nonlinear/verification.json
} finally {
    if($null -ne $lock){$lock.Dispose()};Pop-Location
}
