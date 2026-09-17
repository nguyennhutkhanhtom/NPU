param(
    [ValidateSet('None','Default','Scaled','Both')][string]$Top = 'None',
    [string]$SimBin = 'C:\intelFPGA\20.1\modelsim_ase\win32aloem',
    [string]$Python = 'C:\Users\khanh\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
)
$ErrorActionPreference = 'Stop'
function Invoke-Compile([string]$Library, [string[]]$Files, [string]$Log, [string[]]$Extra = @()) {
    & "$SimBin\vlog.exe" -sv -work $Library @Extra @Files 2>&1 | Out-File -Encoding utf8 $Log
    if ($LASTEXITCODE -ne 0) { throw "Compilation failed: $Log" }
}
function Invoke-Simulation([string]$Design, [string]$Log, [string]$Marker, [string[]]$Extra = @()) {
    & "$SimBin\vsim.exe" -c -onfinish exit -l $Log $Design @Extra -do 'run -all; quit -f' 2>&1 | Out-File -Encoding utf8 "console-$Log"
    if ($LASTEXITCODE -ne 0 -or !(Select-String -LiteralPath $Log -Pattern $Marker -Quiet)) {
        throw "Simulation did not reach expected result: $Design; inspect $Log"
    }
    Write-Output "PASS $Design ($Log)"
}
Push-Location (Join-Path $PSScriptRoot 'sim')
try {
    & $Python ../tools/make_fixtures.py
    if ($LASTEXITCODE -ne 0) { throw 'Fixture generation failed' }
    foreach ($library in @('original','param')) {
        if (!(Test-Path -LiteralPath $library)) {
            & "$SimBin\vlib.exe" $library
            if ($LASTEXITCODE -ne 0) { throw "Library creation failed: $library" }
        }
    }
    $baselineFiles = @(Get-ChildItem -LiteralPath ../baseline -File | Where-Object { $_.Extension -in '.sv','.v' } | ForEach-Object { $_.FullName })
    $rtlFiles = @(Get-ChildItem -LiteralPath '../../Verilog Source code' -File | Where-Object { $_.Extension -in '.sv','.v' } | ForEach-Object { $_.FullName })
    Invoke-Compile 'original' ($baselineFiles + @('tb_replay.sv')) 'compile-original.log'
    Invoke-Compile 'param' ($rtlFiles + @('tb_replay.sv','tb_scaled_alu.sv','tb_scaled_storage.sv','tb_scaled_ddr.sv')) 'compile-final.log'
    Invoke-Simulation 'original.tb_replay' 'replay-original.log' 'REPLAY_DONE cycles=4096' @('+TRACE=trace-original.txt')
    Invoke-Simulation 'param.tb_replay' 'replay-param.log' 'REPLAY_DONE cycles=4096' @('+TRACE=trace-param.txt')
    if ((Get-FileHash trace-original.txt).Hash -ne (Get-FileHash trace-param.txt).Hash) { throw 'Default trace differs from baseline' }
    Write-Output 'PASS default 16-bit trace identical to baseline (4096 cycles)'
    Invoke-Simulation 'param.tb_scaled_alu' 'alu-scaled.log' 'SCALED_ALU_LEGACY_PASS comparisons=524288'
    Invoke-Simulation 'param.tb_scaled_storage' 'tb_scaled_storage.log' 'SCALED_STORAGE_PASS'
    Invoke-Simulation 'param.tb_scaled_ddr' 'tb_scaled_ddr.log' 'SCALED_DDR_PASS'
    if ($Top -in 'Default','Both') {
        Write-Output 'Starting full default top reset/HALT smoke; Starter Edition may take many minutes.'
        Invoke-Compile 'param' @('tb_top.sv') 'compile-top.log'
        Invoke-Simulation 'param.tb_top' 'top-default.log' 'TOP_SMOKE_PASS pc_width=9 word_width=512'
    }
    if ($Top -in 'Scaled','Both') {
        Write-Output 'Starting full scaled top reset/HALT smoke; Starter Edition may take many minutes.'
        Invoke-Compile 'param' @('tb_top.sv') 'compile-top-scaled.log' @('+define+SCALED')
        Invoke-Simulation 'param.tb_top' 'top-scaled.log' 'TOP_SMOKE_PASS pc_width=6 word_width=256'
    }
    & $Python ../tools/summarize.py
    if ($LASTEXITCODE -ne 0) { throw 'Verification summary failed' }
} finally { Pop-Location }
