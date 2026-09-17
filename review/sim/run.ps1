$ErrorActionPreference = 'Stop'
$simBin = 'C:\intelFPGA\20.1\modelsim_ase\win32aloem'
Push-Location $PSScriptRoot
try {
    # Synthetic all-zero fixtures: structural tests only, NOT numeric LUT golden data.
    1..8192 | ForEach-Object { '00000000000000000000000000000000' } | Set-Content mem_init.mem
    1..512 | ForEach-Object { '0000' } | Set-Content exp_content.mif
    1..65536 | ForEach-Object { '0000000000000000' } | Set-Content sigContent.mif
    if (!(Test-Path work)) { & "$simBin\vlib.exe" work }
    $rtlFiles = Get-ChildItem -LiteralPath '../../scale/baseline' -File | Where-Object { $_.Extension -in '.sv','.v' } | ForEach-Object { $_.FullName }
    & "$simBin\vlog.exe" -sv -work work @rtlFiles tb_review.sv 2>&1 | Tee-Object compile.log
    if ($LASTEXITCODE -ne 0) { throw 'RTL compile failed' }
    & "$simBin\vsim.exe" -c -onfinish exit -l simulation.log work.tb_review -do 'run -all; quit -f' 2>&1 | Tee-Object console.log
    if ($LASTEXITCODE -ne 0) { throw 'Simulation failed' }
    if (!(Select-String -LiteralPath simulation.log -Pattern 'EVIDENCE_SUMMARY reproduced=17 checks=17' -Quiet)) {
        throw 'Not all baseline evidence reproduced; inspect simulation.log'
    }
} finally { Pop-Location }
