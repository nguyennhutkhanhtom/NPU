# Compatibility entry point. Historical bug-preserving benches remain in scale/sim.
param(
    [ValidateSet('None','Default','Scaled','Both')][string]$Top='None',
    [string]$SimBin='C:\intelFPGA\20.1\modelsim_ase\win32aloem',
    [string]$Python='C:\Users\khanh\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
)
$ErrorActionPreference='Stop'
$widths=switch($Top) {'Default' {@(16)} 'Scaled' {@(8)} default {@(8,16)}}
& (Join-Path $PSScriptRoot '../functional/run.ps1') -Group All -Widths $widths -SimBin $SimBin -Python $Python
