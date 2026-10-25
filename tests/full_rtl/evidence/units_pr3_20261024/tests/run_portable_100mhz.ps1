param(
    [Parameter(Mandatory=$true)][ValidatePattern('^[a-z][a-z0-9_-]{0,63}$')][string]$WorkLibraryName,
    [Parameter(Mandatory=$true)][ValidatePattern('^[a-z][a-z0-9_-]{0,63}$')][string]$EvidenceTag
)
$ErrorActionPreference='Stop'
$repo=Split-Path (Split-Path $PSScriptRoot)
$unit=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'unit_results.json') -Raw | ConvertFrom-Json
if ($unit.status -ne 'PASS') {throw 'Current all-seven PASS required before portable elaboration'}
if (Get-Process vsimk -ErrorAction SilentlyContinue) {throw 'Questa simulation still active'}
foreach ($property in $unit.rtl_sources.PSObject.Properties) {
    if ((Get-FileHash -LiteralPath (Join-Path $repo ('Verilog Source code/'+$property.Name))).Hash.ToLower() -ne $property.Value) {
        throw 'RTL changed since unit compilation'
    }
}
$output=Join-Path $repo ('docs/verification/'+$EvidenceTag)
if (Test-Path -LiteralPath $output) {throw 'Evidence tag already exists'}
New-Item -ItemType Directory -Path $output | Out-Null
$relativeOutput='docs/verification/'+$EvidenceTag
$sim='C:/altera_lite/25.1std/questa_fse/win64/vsim.exe'
$arguments=@('-c','-onfinish','exit','-lib',('tests/full_rtl/build/'+$WorkLibraryName),
    ('-voptargs=-duselectreport='+$relativeOutput+'/design_units.json'),'-gUSE_QUARTUS_MEMORY=0',
    '-l',(Join-Path $output 'elaborate.log'),'llm_soc','-do','run 0; quit -f')
[ordered]@{executable=$sim;arguments=$arguments;started_utc=[DateTime]::UtcNow.ToString('o')} |
    ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $output 'commands.json') -Encoding utf8
Push-Location $repo
try {
    & $sim @arguments *> (Join-Path $output 'elaborate.console')
    if ($LASTEXITCODE -ne 0) {throw 'Portable elaboration failed'}
    $log=Get-Content -LiteralPath (Join-Path $output 'elaborate.log') -Raw
    if ($log -notmatch 'Errors: 0, Warnings: 0' -or $log -match '\*\* (Warning|Error|Fatal)') {
        throw 'Portable elaboration diagnostics are not clean'
    }
    $bindings=Get-Content -LiteralPath (Join-Path $output 'design_units.json') -Raw | ConvertFrom-Json
    $modules=@($bindings.DESIGN_UNITS | ForEach-Object {$_.UNIT} | Where-Object {$_.TYPE -eq 'MODULE'})
    $names=@($modules | ForEach-Object {$_.PRIMARY} | Sort-Object -Unique)
    if ('llm_soc' -notin $names -or 'sram_word_tile' -notin $names -or
        @($names | Where-Object {$_ -match '^(alt|altera|cyclone|arria|stratix|lpm_)'}).Count -gt 0 -or
        $log -match '# Loading .*?(altera|altsyncram|cyclone)') {throw 'Unexpected portable module bindings'}
    Copy-Item -LiteralPath $PSCommandPath -Destination (Join-Path $output 'runner.ps1')
    $archives=[ordered]@{}
    Get-ChildItem -LiteralPath $output -File | ForEach-Object {$archives[$_.Name]=(Get-FileHash -LiteralPath $_.FullName).Hash.ToLower()}
    [ordered]@{status='ELABORATION_PASS';completed_utc=[DateTime]::UtcNow.ToString('o');top='llm_soc';
        parameter=@{USE_QUARTUS_MEMORY=0};rtl_sources=$unit.rtl_sources;module_names=$names;
        module_design_units=$modules.Count;errors=0;warnings=0;vendor_memory_library_loaded=$false;
        archives=$archives;scope='run 0; vendor-free full-top elaboration; no application or ASIC signoff'} |
        ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $output 'results.json') -Encoding utf8
} finally {Pop-Location}
Write-Output 'PORTABLE_100MHZ_ELABORATION_PASS'
