$ErrorActionPreference = 'Stop'
$simBin = 'C:\intelFPGA\20.1\modelsim_ase\win32aloem'
Push-Location $PSScriptRoot
try {
    # Build first if invoked standalone; creates only review fixtures/libraries.
    if (!(Test-Path -LiteralPath work)) { & ./run_extended.ps1 }
    & "$simBin\vlog.exe" -sv -work work scaled_profiles.sv tb_scaled_leaf.sv tb_param_probe.sv 2>&1 | Tee-Object compile-profiles.log
    if ($LASTEXITCODE -ne 0) { throw 'Profile/testbench compile failed' }
    & "$simBin\vsim.exe" -c -onfinish exit -l scaled-profile.log work.tb_scaled_profiles -do 'run -all; quit -f' 2>&1 | Out-File console-profile.log
    if ($LASTEXITCODE -ne 0 -or !(Select-String -LiteralPath scaled-profile.log -Pattern 'SCALED_PROFILE_VALID' -Quiet)) { throw 'Invalid target profile' }
    & "$simBin\vsim.exe" -c -onfinish exit -l scaled-leaf.log work.tb_scaled_leaf -do 'run -all; quit -f' 2>&1 | Out-File console-leaf.log
    if ($LASTEXITCODE -ne 0 -or !(Select-String -LiteralPath scaled-leaf.log -Pattern 'SCALED_LEAF_PASS' -Quiet)) { throw 'Scaled leaf smoke failed' }
    & "$simBin\vsim.exe" -c -onfinish exit -l param-probe.log work.tb_param_probe -do 'run -all; quit -f' 2>&1 | Out-File console-param-probe.log
    $probeExit = $LASTEXITCODE
    if ($probeExit -eq 0 -or !(Select-String -LiteralPath param-probe.log -Pattern 'vsim-3906' -Quiet)) { throw 'Expected DATA_WIDTH=8 array-port incompatibility not reproduced' }
    Write-Output 'Profile consistency PASS; scaled leaf smoke PASS; DATA_WIDTH=8 expected elaboration failure reproduced.'
} finally { Pop-Location }
