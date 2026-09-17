param(
    [string]$SimBin = 'C:\intelFPGA\20.1\modelsim_ase\win32aloem',
    [string]$Python = 'C:\Users\khanh\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
)
$ErrorActionPreference = 'Stop'
& $Python (Join-Path $PSScriptRoot 'audit.py') --sim-bin $SimBin
if ($LASTEXITCODE -eq 1) {
    Write-Output 'Retest completed: exact Q4.12 reference mismatch; see REVIEW.md.'
} elseif ($LASTEXITCODE -ne 0) {
    throw "Audit could not complete: exit $LASTEXITCODE"
}
exit $LASTEXITCODE
