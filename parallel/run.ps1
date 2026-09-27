param(
    [int[]]$Cases=@(0,1,2,3,4,5,6,7,8,9,10,11),
    [string]$SimBin='C:\intelFPGA\20.1\modelsim_ase\win32aloem',
    [string]$Python='C:\Users\khanh\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe',
    [switch]$SkipNormRegression
)
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot
$sim=Join-Path $PSScriptRoot 'sim'
New-Item -ItemType Directory -Force $sim | Out-Null
$results=[ordered]@{}
$runLock=$null
Push-Location $sim
try {
    $runLock=[IO.File]::Open((Join-Path $sim '.run.lock'),'OpenOrCreate','ReadWrite','None')
    if(@($Cases | Where-Object {$_ -lt 0 -or $_ -gt 11}).Count) {throw 'Supported cases: 0..11'}
    if(!(Test-Path work)) {
        & "$SimBin/vlib.exe" work *> create.log
        if($LASTEXITCODE -ne 0) {throw 'Library creation failed'}
    }
    Copy-Item -LiteralPath (Join-Path $repo 'data/normContent.mif') -Destination normContent.mif
    Copy-Item -LiteralPath (Join-Path $repo 'Verilog Source code/sigContent.mif') -Destination sigContent.mif
    # EXP is inactive in these scheduling tests; SIG uses the real delivered LUT.
    [IO.File]::WriteAllLines((Join-Path $sim 'exp_content.mif'),[string[]](@('0000')*512))
    [IO.File]::WriteAllLines((Join-Path $sim 'instruction.mem'),[string[]](@('1111111111111')*512))
    $rtl=@(Get-ChildItem -LiteralPath (Join-Path $repo 'Verilog Source code') -File | Where-Object {$_.Extension -in '.sv','.v'})
    $tests=@((Join-Path $PSScriptRoot 'tests/tb_parallel.sv'),(Join-Path $repo 'tmatmul/sim/tb_core.sv'))
    & "$SimBin/vlog.exe" -sv -work work @($rtl.FullName) @tests *> compile.log
    if($LASTEXITCODE -ne 0) {Get-Content compile.log -Tail 30;throw 'Compile failed'}
    foreach($case in $Cases) {
        & "$SimBin/vsim.exe" -c -onfinish exit -wlf "case-$case.wlf" -l "case-$case.log" work.tb_parallel "-gCASE=$case" -do 'do ../record.do; run -all; quit -f' *> "case-$case.console"
        if($LASTEXITCODE -ne 0 -or !(Select-String -LiteralPath "case-$case.log" -SimpleMatch 'PARALLEL_PASS' -Quiet) -or
           (Select-String -LiteralPath "case-$case.log" -Pattern '^# \*\* (Fatal|Error):' -Quiet)) {
            Get-Content "case-$case.log" -Tail 20;throw "Parallel case $case failed"
        }
        $marker=(Select-String -LiteralPath "case-$case.log" -SimpleMatch 'PARALLEL_PASS').Line
        $results["case-$case"]=$marker
        Write-Output $marker
    }
    & "$SimBin/vsim.exe" -c -onfinish exit -l core.log work.tb_core -do 'run -all; quit -f' *> core.console
    if($LASTEXITCODE -ne 0 -or !(Select-String -LiteralPath core.log -SimpleMatch 'CORE_PASS' -Quiet) -or
       (Select-String -LiteralPath core.log -Pattern '^# \*\* (Fatal|Error):' -Quiet)) {
        Get-Content core.log -Tail 20;throw 'Existing TM core regression failed'
    }
    $results['core']=(Select-String -LiteralPath core.log -SimpleMatch 'CORE_PASS').Line
    Write-Output $results['core']
    if(!$SkipNormRegression) {
        & $Python (Join-Path $PSScriptRoot 'generate_norm_fixtures.py') *> norm-generate.log
        if($LASTEXITCODE -ne 0) {Get-Content norm-generate.log -Tail 15;throw 'NORM fixtures failed'}
        $normTests=@((Join-Path $repo 'norm/tests/tb_norm_core.sv'),(Join-Path $repo 'norm/tests/tb_norm_memory.sv'))
        & "$SimBin/vlog.exe" -sv -work work @normTests *> norm-compile.log
        if($LASTEXITCODE -ne 0) {Get-Content norm-compile.log -Tail 20;throw 'NORM regression compile failed'}
        $tests += $normTests
        Push-Location norm
        try {
            foreach($tm in @(0,1)) {
                & "$SimBin/vsim.exe" -c -onfinish exit -l "core-$tm.log" ../work.tb_norm_core "-gUSE_TM=$tm" -do 'run -all; quit -f' *> "core-$tm.console"
                if($LASTEXITCODE -ne 0 -or !(Select-String -LiteralPath "core-$tm.log" -SimpleMatch 'NORM_CORE_PASS' -Quiet) -or
                   (Select-String -LiteralPath "core-$tm.log" -Pattern '^# \*\* (Fatal|Error):' -Quiet)) {
                    Get-Content "core-$tm.log" -Tail 20;throw "NORM core regression $tm failed"
                }
                $results["norm-core-$tm"]=(Select-String -LiteralPath "core-$tm.log" -SimpleMatch 'NORM_CORE_PASS').Line
                Write-Output $results["norm-core-$tm"]
            }
            & "$SimBin/vsim.exe" -c -onfinish exit -l memory.log ../work.tb_norm_memory -do 'run -all; quit -f' *> memory.console
            if($LASTEXITCODE -ne 0 -or !(Select-String -LiteralPath memory.log -SimpleMatch 'NORM_MEMORY_PASS' -Quiet) -or
               (Select-String -LiteralPath memory.log -Pattern '^# \*\* (Fatal|Error):' -Quiet)) {
                Get-Content memory.log -Tail 20;throw 'NORM memory regression failed'
            }
            $results['norm-memory']=(Select-String -LiteralPath memory.log -SimpleMatch 'NORM_MEMORY_PASS').Line
            Write-Output $results['norm-memory']
        } finally {Pop-Location}
    }
    $hashes=[ordered]@{}
    foreach($path in @($rtl.FullName)+$tests+@($PSCommandPath,(Join-Path $PSScriptRoot 'record.do'),(Join-Path $PSScriptRoot 'generate_norm_fixtures.py'),
        (Join-Path $repo 'norm/generate_tests.py'),(Join-Path $repo 'python/generate_norm_lut.py'),
        (Join-Path $repo 'data/normContent.mif'),(Join-Path $repo 'Verilog Source code/sigContent.mif'))) {
        $hashes[$path.Substring($repo.Length+1).Replace('\','/')]=(Get-FileHash -LiteralPath $path).Hash.ToLower()
    }
    [ordered]@{status='PASS';utc=[DateTime]::UtcNow.ToString('o');tests=$results;sources=$hashes;
        scope='TM/ALU overlap and ordered LDV/STV/TM/HALT, RTL simulation';synthesis_run=$false} |
        ConvertTo-Json -Depth 5 | Set-Content (Join-Path $PSScriptRoot 'verification.json') -Encoding utf8
} finally {
    if($null -ne $runLock) {$runLock.Dispose()}
    Pop-Location
}
