param([string]$SimBin='C:/intelFPGA/20.1/modelsim_ase/win32aloem',
      [string]$RtlDir='Verilog Source code')
$ErrorActionPreference='Stop'
$repo=Split-Path (Split-Path $PSScriptRoot)
$build=Join-Path $PSScriptRoot 'build'
New-Item -ItemType Directory -Path $build -Force | Out-Null
$rtl=if([IO.Path]::IsPathRooted($RtlDir)) {$RtlDir} else {Join-Path $repo $RtlDir}
$hashes=[ordered]@{}
Get-ChildItem -LiteralPath $rtl -File | Where-Object {$_.Extension -in '.sv','.v','.svh','.mem'} | Sort-Object Name | ForEach-Object {
    $hashes[$_.Name]=(Get-FileHash -LiteralPath $_.FullName).Hash.ToLower()
}
$testHashes=[ordered]@{}
Get-ChildItem -LiteralPath $PSScriptRoot -File | Where-Object {$_.Name -like 'tb_*.sv' -or $_.Name -eq 'run_units.ps1'} | Sort-Object Name | ForEach-Object {
    $testHashes[$_.Name]=(Get-FileHash -LiteralPath $_.FullName).Hash.ToLower()
}
[ordered]@{status='RUNNING';scope='Synthetic units and graph only';rtl_dir=$rtl;rtl_sources=$hashes;test_sources=$testHashes} |
    ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'unit_results.json') -Encoding utf8
$evidence=[ordered]@{}
try {
$packages=@('npu_pkg.sv','llm_pkg.sv')
$sources=@($packages | ForEach-Object {Join-Path $rtl $_})+
    @(Get-ChildItem -LiteralPath $rtl -File | Where-Object {$_.Extension -in '.sv','.v' -and $_.Name -notin $packages} | Sort-Object Name | ForEach-Object {$_.FullName})+
    @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter 'tb_*.sv' -File | Sort-Object Name | ForEach-Object {$_.FullName})
$list=Join-Path $build 'sources.f'
$sources | ForEach-Object {'"'+$_.Replace('\','/')+'"'} | Set-Content -LiteralPath $list -Encoding utf8
$library=Join-Path $build 'work'
& "$SimBin/vlib.exe" $library *> (Join-Path $build 'vlib.log')
if($LASTEXITCODE -ne 0) {throw 'Cannot create unit test library'}
& "$SimBin/vlog.exe" -sv -svinputport=var -work $library "+incdir+$rtl" -f $list -l (Join-Path $build 'compile.log') *> (Join-Path $build 'compile.console')
if($LASTEXITCODE -ne 0) {Get-Content (Join-Path $build 'compile.log') -Tail 15;throw 'Unit compile failed'}
foreach($top in @('tb_llm_math','tb_llm_ram','tb_llm_protocol','tb_llm_selection','tb_llm_operators','tb_llm_graph')) {
    $log=Join-Path $build "$top.log"
    & "$SimBin/vsim.exe" -c -onfinish exit -L $library -lib $library -l $log $top -do 'run -all; quit -f' *> "$log.console"
    if($LASTEXITCODE -ne 0 -or !(Select-String -LiteralPath $log -Pattern '_PASS' -Quiet) -or (Select-String -LiteralPath $log -Pattern '^# \*\* (Fatal|Error)' -Quiet)) {
        Get-Content -LiteralPath $log -Tail 15;throw "Unit simulation failed: $top"
    }
    $marker=(Select-String -LiteralPath $log -Pattern '_PASS' | Select-Object -Last 1).Line
    $evidence[$top]=$marker;Write-Output $marker
}
Get-ChildItem -LiteralPath $rtl -File | Where-Object {$_.Extension -in '.sv','.v','.svh','.mem'} | Sort-Object Name | ForEach-Object {
    if($hashes[$_.Name] -ne (Get-FileHash -LiteralPath $_.FullName).Hash.ToLower()) {throw 'RTL changed during unit testing'}
}
Get-ChildItem -LiteralPath $PSScriptRoot -File | Where-Object {$_.Name -like 'tb_*.sv' -or $_.Name -eq 'run_units.ps1'} | Sort-Object Name | ForEach-Object {
    if($testHashes[$_.Name] -ne (Get-FileHash -LiteralPath $_.FullName).Hash.ToLower()) {throw 'Test sources changed during unit testing'}
}
[ordered]@{status='PASS';scope='Synthetic arithmetic/protocol/operators/autonomous graph; no pretrained application';rtl_dir=$rtl;verified_utc=[DateTime]::UtcNow.ToString('o');tests=$evidence;rtl_sources=$hashes;test_sources=$testHashes} |
    ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'unit_results.json') -Encoding utf8
} catch {
    [ordered]@{status='FAIL';failure=$_.Exception.Message;verified_utc=[DateTime]::UtcNow.ToString('o');rtl_dir=$rtl;tests=$evidence;rtl_sources=$hashes;test_sources=$testHashes} |
        ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'unit_results.json') -Encoding utf8
    throw
}
