$ErrorActionPreference = 'Stop'
$simBin = 'C:\intelFPGA\20.1\modelsim_ase\win32aloem'
Push-Location $PSScriptRoot
try {
    # These zero fixtures are structural test data, never numerical golden LUTs.
    Copy-Item -LiteralPath ../sim/mem_init.mem,../sim/exp_content.mif,../sim/sigContent.mif -Destination .
    if (!(Test-Path -LiteralPath work)) { & "$simBin\vlib.exe" work }
    $rtlFiles = Get-ChildItem -LiteralPath '../../Verilog Source code' -File | Where-Object { $_.Extension -in '.sv','.v' } | ForEach-Object { $_.FullName }
    & "$simBin\vlog.exe" -sv -work work @rtlFiles tb_extended.sv 2>&1 | Tee-Object compile-extended.log
    if ($LASTEXITCODE -ne 0) { throw 'Compile failed' }
    & "$simBin\vsim.exe" -c -onfinish exit -l simulation-extended.log work.tb_extended -do 'run -all; quit -f' 2>&1 | Tee-Object console-extended.log
    if ($LASTEXITCODE -ne 0) { throw 'Simulation failed' }
    if (!(Select-String -LiteralPath simulation-extended.log -Pattern 'EXTENDED_SUMMARY reproduced=20 checks=20' -Quiet)) { throw 'Evidence mismatch' }
} finally { Pop-Location }
