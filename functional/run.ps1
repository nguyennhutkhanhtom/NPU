param(
    [ValidateSet('All','Alu','Storage','Norm','Ternary','Ddr','Core','Control','Guards')][string[]]$Group=@('All'),
    [int[]]$Widths=@(8,16),
    [switch]$RegenerateAssets,
    [string]$SimBin='C:\intelFPGA\20.1\modelsim_ase\win32aloem',
    [string]$Python='C:\Users\khanh\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
$runLock=$null
Push-Location $root
try {
    if(@($Widths | Where-Object {$_ -notin @(8,16)}).Count) {throw 'Supported widths: 8,16'}
    New-Item -ItemType Directory -Force functional/sim | Out-Null
    # A file handle prevents simultaneous writers to the ModelSim library.
    $runLock=[IO.File]::Open((Join-Path $root 'functional/sim/.run.lock'),
        [IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    $libraryLock=Join-Path $root 'functional/sim/work/_lock'
    if(Test-Path -LiteralPath $libraryLock) {
        $owner=Get-Content -Raw -LiteralPath $libraryLock
        if($owner -match 'pid\s*=\s*(\d+)') {
            $ownerPid=[int]$Matches[1]
            if(Get-Process -Id $ownerPid -ErrorAction SilentlyContinue) {throw "Simulator library is in use by PID $ownerPid"}
            Remove-Item -LiteralPath $libraryLock
        } else {throw 'Unrecognized simulator library lock; inspect functional/sim/work/_lock'}
    }
    if($RegenerateAssets -or !(Test-Path functional/assets/manifest.json)) {
        & $Python functional/tools/generate.py
        if($LASTEXITCODE -ne 0) {throw 'Numeric asset generation failed'}
    }
    if(!(Test-Path functional/sim/work)) {
        & "$SimBin/vlib.exe" functional/sim/work
        if($LASTEXITCODE -ne 0) {throw 'Library creation failed'}
    }
    $rtl=@(Get-ChildItem -LiteralPath 'Verilog Source code' -File | Where-Object {$_.Extension -in '.sv','.v'} | ForEach-Object {$_.FullName})
    $tests=@(Get-ChildItem functional/sim/tb_*.sv | ForEach-Object {$_.FullName})
    & "$SimBin/vlog.exe" -sv -work functional/sim/work @rtl @tests *> functional/sim/compile.log
    if($LASTEXITCODE -ne 0) {
        Get-Content functional/sim/compile.log -Tail 16
        throw 'Compile failed; see functional/sim/compile.log'
    }
    $sources=@{}
    foreach($path in ($rtl+$tests+@((Join-Path $root 'functional/tools/generate.py')))) {
        $sources[$path.Substring($root.Length+1).Replace('\','/')]=(Get-FileHash -LiteralPath $path).Hash.ToLower()
    }
    @{sources=$sources;compiled_utc=[DateTime]::UtcNow.ToString('o')} | ConvertTo-Json -Depth 4 |
        Set-Content -Encoding utf8 functional/sim/build.json
    $groups=if($Group -contains 'All') {@('Alu','Storage','Norm','Ddr','Control','Ternary','Core','Guards')} else {$Group}
    $guardMessages=@('Invalid memory packing/depth/pointer parameters','EXP requires a full',
        'Accumulator needs nine guard bits','Invalid register pointer width','Invalid RMS parameters',
        'Invalid DIV format','Missing EXP LUT','Invalid PC depth/width','Invalid memory packing/depth/pointer parameters',
        'SIG supports matching')
    foreach($g in $groups) {
        foreach($width in $Widths) {
            if($g -eq 'Guards') {
                foreach($case in 0..9) {
                    $log="functional/sim/guard-$width-$case.log"
                    & "$SimBin/vsim.exe" -c -onfinish exit -l $log 'functional/sim/work.tb_guards' "-gW=$width" "-gCASE=$case" -do 'run -all; quit -f' *> "$log.console"
                    if(!(Select-String -LiteralPath $log -SimpleMatch $guardMessages[$case] -Quiet) -or
                       (Select-String -LiteralPath $log -SimpleMatch 'GUARD_MISSED' -Quiet)) {
                        Get-Content $log -Tail 12
                        throw "Expected guard rejection missing W=$width CASE=$case"
                    }
                    Add-Content -LiteralPath $log "GUARD_EXPECTED_PASS W=$width CASE=$case"
                }
                Write-Output "GUARDS_PASS W=$width cases=10"
            } else {
                $test='tb_'+$g.ToLower()
                $log="functional/sim/$test-$width.log"
                & "$SimBin/vsim.exe" -c -onfinish exit -l $log "functional/sim/work.$test" "-gW=$width" -do 'run -all; quit -f' *> "$log.console"
                if($LASTEXITCODE -ne 0 -or !(Select-String -LiteralPath $log -Pattern ('^# '+$g.ToUpper()+'_PASS') -Quiet) -or
                   (Select-String -LiteralPath $log -Pattern '^# \*\* (Fatal|Error):' -Quiet)) {
                    Get-Content $log -Tail 16
                    throw "Simulation failed: $test W=$width"
                }
                Select-String -LiteralPath $log -Pattern ('^# '+$g.ToUpper()+'_PASS') | ForEach-Object {$_.Line}
            }
        }
    }
    if($Group -contains 'All' -and $Widths -contains 8 -and $Widths -contains 16) {
        & $Python functional/tools/report.py
        if($LASTEXITCODE -ne 0) {throw 'Verification summary failed'}
    }
} finally {
    if($null -ne $runLock) {$runLock.Dispose()}
    Pop-Location
}
