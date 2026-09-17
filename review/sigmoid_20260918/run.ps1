param(
    [string]$SimBin = 'C:\intelFPGA\20.1\modelsim_ase\win32aloem',
    [string]$Python = 'C:\Users\khanh\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
)
$ErrorActionPreference = 'Stop'
& $Python (Join-Path $PSScriptRoot 'audit.py') --sim-bin $SimBin
if ($LASTEXITCODE -ne 0) { throw "Sigmoid audit failed to execute or design failed: exit $LASTEXITCODE (see REVIEW.md and verification.json)" }
