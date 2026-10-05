param([string]$SimBin='C:/intelFPGA/20.1/modelsim_ase/win32aloem',
      [string]$RtlDir='Verilog Source code',
      [switch]$UnitsOnly,
      [switch]$Questa,
      [string]$MemoryModelManifest='',
      [string]$TimingManifest='',
      [string]$Python='C:/Users/khanh/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe',
      [ValidatePattern('^[a-z][a-z0-9_-]{0,63}$')][string]$WorkLibraryName='work',
      [ValidatePattern('^[a-z][a-z0-9_-]{0,63}$')][string]$EvidenceTag='',
      [ValidateSet('tb_quartus_memory','tb_llm_math','tb_llm_ram','tb_llm_protocol','tb_llm_selection','tb_llm_operators','tb_llm_graph')][string[]]$OnlyTop=@())
$ErrorActionPreference='Stop'
$repo=Split-Path (Split-Path $PSScriptRoot)
$build=Join-Path $PSScriptRoot 'build'
New-Item -ItemType Directory -Path $build -Force | Out-Null
$memoryLibrary='altera_mf_ver'
$runnerHashes=[ordered]@{}
if ($Questa -and !$MemoryModelManifest) {throw 'Questa requires a verified explicit RAM model manifest'}
if ($MemoryModelManifest) {
    if (!$TimingManifest) {throw 'TimingManifest is required to identify the installed RAM model'}
    & $Python (Join-Path $PSScriptRoot 'memory_model.py') --timing $TimingManifest --sim-bin $SimBin --verify-manifest $MemoryModelManifest
    if ($LASTEXITCODE -ne 0) {throw 'RAM model integrity failed'}
    $memoryLibrary=(Get-Content -LiteralPath $MemoryModelManifest -Raw | ConvertFrom-Json).library
    $runnerHashes['tests/full_rtl/memory_model.py']=(Get-FileHash (Join-Path $PSScriptRoot 'memory_model.py')).Hash.ToLower()
}
$rtl=if([IO.Path]::IsPathRooted($RtlDir)) {$RtlDir} else {Join-Path $repo $RtlDir}
$hashes=[ordered]@{}
Get-ChildItem -LiteralPath $rtl -File | Where-Object {$_.Extension -in '.sv','.v','.svh','.mem'} | Sort-Object Name | ForEach-Object {
    $hashes[$_.Name]=(Get-FileHash -LiteralPath $_.FullName).Hash.ToLower()
}
$testHashes=[ordered]@{}
Get-ChildItem -LiteralPath $PSScriptRoot -File | Where-Object {$_.Name -like 'tb_*.sv' -or $_.Name -eq 'run_units.ps1'} | Sort-Object Name | ForEach-Object {
    $testHashes[$_.Name]=(Get-FileHash -LiteralPath $_.FullName).Hash.ToLower()
}
$startedUtc=[DateTime]::UtcNow
if (!$EvidenceTag) {$EvidenceTag='run_'+$startedUtc.ToString('yyyyMMdd_HHmmss')}
$initialSnapshot=Join-Path $build ($EvidenceTag+'_modelsim_start.json')
if (Test-Path -LiteralPath $initialSnapshot) {throw 'Initial evidence tag already exists; choose a new EvidenceTag'}
[ordered]@{status='RUNNING';scope='Synthetic units and graph only';started_utc=$startedUtc.ToString('o');rtl_dir=$rtl;rtl_sources=$hashes;test_sources=$testHashes} |
    ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'unit_results.json') -Encoding utf8
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'unit_results.json') -Destination $initialSnapshot
$evidence=[ordered]@{}
$logs=[ordered]@{}
Push-Location $repo
try {
$packages=@('npu_pkg.sv','llm_pkg.sv')
$sources=@($packages | ForEach-Object {Join-Path $rtl $_})+
    @(Get-ChildItem -LiteralPath $rtl -File | Where-Object {$_.Extension -in '.sv','.v' -and $_.Name -notin $packages} | Sort-Object Name | ForEach-Object {$_.FullName})+
    @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter 'tb_*.sv' -File | Sort-Object Name | ForEach-Object {$_.FullName})
$list=Join-Path $build 'sources.f'
$sources | ForEach-Object {'"'+$_.Replace('\','/')+'"'} | Set-Content -LiteralPath $list -Encoding utf8
$library=Join-Path $build $WorkLibraryName
& "$SimBin/vlib.exe" $library *> (Join-Path $build 'vlib.log')
if($LASTEXITCODE -ne 0) {throw 'Cannot create unit test library'}
& "$SimBin/vlog.exe" -sv -svinputport=var -work $library "+incdir+$rtl" -f $list -l (Join-Path $build 'compile.log') *> (Join-Path $build 'compile.console')
if($LASTEXITCODE -ne 0) {Get-Content (Join-Path $build 'compile.log') -Tail 15;throw 'Unit compile failed'}
$tops=@('tb_quartus_memory','tb_llm_math','tb_llm_ram','tb_llm_protocol','tb_llm_selection','tb_llm_operators')
if (!$UnitsOnly) {$tops += 'tb_llm_graph'}
if ($OnlyTop.Count) {$tops=$OnlyTop}
foreach($top in $tops) {
    $log=Join-Path $build "$top.log"
    $arguments=@('-c','-onfinish','exit')
    $simulationLibrary=$library
    $simulationMemory=$memoryLibrary
    if ($Questa) {
        # Questa vopt interprets -lib as a qualified design-unit name. Use
        # repository-relative forward-slash paths, avoiding the drive/space
        # parsing of an absolute Windows path in library.top.
        $simulationLibrary='tests/full_rtl/build/'+$WorkLibraryName
        $simulationMemory=[IO.Path]::GetRelativePath($repo,$memoryLibrary).Replace('\','/')
    }
    $duReport='tests/full_rtl/build/'+$EvidenceTag+'_'+$top+'_design_units.json'
    if ($Questa) {$arguments+='-voptargs=-duselectreport='+$duReport}
    $arguments+=@('-L',$simulationMemory,'-L',$simulationLibrary,'-lib',$simulationLibrary,'-l',$log,$top,'-do','run -all; quit -f')
    & "$SimBin/vsim.exe" @arguments *> "$log.console"
    if($LASTEXITCODE -ne 0 -or !(Select-String -LiteralPath $log -Pattern '_PASS' -Quiet) -or (Select-String -LiteralPath $log -Pattern '^# \*\* (Fatal|Error|Warning)|UI-Msg \(Error\)' -Quiet)) {
        Get-Content -LiteralPath $log -Tail 15;throw "Unit simulation failed: $top"
    }
    $marker=(Select-String -LiteralPath $log -Pattern '_PASS' | Select-Object -Last 1).Line
    $evidence[$top]=$marker;Write-Output $marker
    $logs[$top]=[ordered]@{log='tests/full_rtl/build/'+$top+'.log';sha256=(Get-FileHash -LiteralPath $log).Hash.ToLower()}
    if ($Questa) {
        $checks=@('--timing',$TimingManifest,'--sim-bin',$SimBin,'--verify-manifest',$MemoryModelManifest,'--design-units',$duReport)
        if ($top -in @('tb_quartus_memory','tb_llm_protocol','tb_llm_selection','tb_llm_graph')) {$checks+='--require-memory'}
        & $Python (Join-Path $PSScriptRoot 'memory_model.py') @checks
        if ($LASTEXITCODE -ne 0) {throw 'Actual RAM elaboration binding failed'}
        $logs[$top]['design_units']=[ordered]@{file=$duReport;sha256=(Get-FileHash -LiteralPath $duReport).Hash.ToLower()}
    }
}
Get-ChildItem -LiteralPath $rtl -File | Where-Object {$_.Extension -in '.sv','.v','.svh','.mem'} | Sort-Object Name | ForEach-Object {
    if($hashes[$_.Name] -ne (Get-FileHash -LiteralPath $_.FullName).Hash.ToLower()) {throw 'RTL changed during unit testing'}
}
Get-ChildItem -LiteralPath $PSScriptRoot -File | Where-Object {$_.Name -like 'tb_*.sv' -or $_.Name -eq 'run_units.ps1'} | Sort-Object Name | ForEach-Object {
    if($testHashes[$_.Name] -ne (Get-FileHash -LiteralPath $_.FullName).Hash.ToLower()) {throw 'Test sources changed during unit testing'}
}
$status=if ($OnlyTop.Count) {'SELECTED_GROUPS_PASS'} elseif ($UnitsOnly) {'SIX_GROUPS_PASS_GRAPH_PENDING'} else {'PASS'}
foreach ($name in $runnerHashes.Keys) {
    if ((Get-FileHash -LiteralPath (Join-Path $repo $name)).Hash.ToLower() -ne $runnerHashes[$name]) {throw 'Memory verification runner changed during unit testing'}
}
[ordered]@{status=$status;scope='Synthetic arithmetic/protocol/operators; graph required for application gate';rtl_dir=$rtl;verified_utc=[DateTime]::UtcNow.ToString('o');tests=$evidence;evidence=$logs;runner_sources=$runnerHashes;memory_model_manifest=$MemoryModelManifest;rtl_sources=$hashes;test_sources=$testHashes} |
    ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'unit_results.json') -Encoding utf8
} catch {
    [ordered]@{status='FAIL';failure=$_.Exception.Message;verified_utc=[DateTime]::UtcNow.ToString('o');rtl_dir=$rtl;tests=$evidence;rtl_sources=$hashes;test_sources=$testHashes} |
        ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'unit_results.json') -Encoding utf8
    throw
} finally {Pop-Location}
