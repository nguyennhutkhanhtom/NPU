$ErrorActionPreference='Stop'
$repo=Split-Path (Split-Path (Split-Path $PSScriptRoot))
$unit=Get-Content -LiteralPath (Join-Path $repo 'tests/full_rtl/unit_results.json') -Raw | ConvertFrom-Json
if ($unit.status -ne 'PASS') {throw 'Wait for current all-seven PASS before reusing its compiled library'}
if (Get-Process vsimk -ErrorAction SilentlyContinue) {throw 'Questa simulation still active'}
foreach ($property in $unit.rtl_sources.PSObject.Properties) {
    $actual=(Get-FileHash -LiteralPath (Join-Path $repo ('Verilog Source code/'+$property.Name))).Hash.ToLower()
    if ($actual -ne $property.Value) {throw 'RTL changed since compiled unit PASS'}
}
$output=Join-Path $PSScriptRoot 'portable_cache1'
if (Test-Path -LiteralPath $output) {throw 'Portable elaboration output already exists'}
New-Item -ItemType Directory -Path $output | Out-Null
$sim='C:/altera_lite/25.1std/questa_fse/win64/vsim.exe'
$arguments=@('-c','-onfinish','exit','-lib','tests/full_rtl/build/cache1_questa_work',
    '-voptargs=-duselectreport=tests/full_rtl/build/portable_cache1/design_units.json',
    '-gUSE_QUARTUS_MEMORY=0','-l',(Join-Path $output 'elaborate.log'),'llm_soc','-do','run 0; quit -f')
[ordered]@{executable=$sim;arguments=$arguments;started_at_utc=[DateTime]::UtcNow.ToString('o');compiled_unit_evidence='tests/full_rtl/evidence/cache1_all_units/results.json'} |
    ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $output 'commands.json') -Encoding utf8
Push-Location $repo
try {
    & $sim @arguments *> (Join-Path $output 'elaborate.console')
    if ($LASTEXITCODE -ne 0) {throw 'Portable full-top elaboration failed; preserve fresh logs'}
    if (!(Select-String -LiteralPath (Join-Path $output 'elaborate.log') -Pattern 'Errors: 0, Warnings: 0' -Quiet)) {throw 'Portable elaboration lacks clean completion'}
} finally {Pop-Location}
Write-Output 'PORTABLE_CACHE1_ELABORATION_COMPLETE: run0/no weights/no vendor memory -L argument'
