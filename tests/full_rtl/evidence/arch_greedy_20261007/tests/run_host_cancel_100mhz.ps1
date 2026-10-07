param(
    [Parameter(Mandatory=$true)][ValidatePattern('^[a-z][a-z0-9_-]{0,63}$')][string]$WorkLibraryName,
    [Parameter(Mandatory=$true)][ValidatePattern('^[a-z][a-z0-9_-]{0,63}$')][string]$EvidenceTag
)
$ErrorActionPreference='Stop'
$repo=Split-Path (Split-Path $PSScriptRoot)
if (Get-Process vsimk -ErrorAction SilentlyContinue) {throw 'Questa simulation still active'}
$output=Join-Path $PSScriptRoot ('evidence/'+$EvidenceTag)
$library=Join-Path $PSScriptRoot ('build/'+$WorkLibraryName)
if ((Test-Path -LiteralPath $output) -or (Test-Path -LiteralPath $library)) {throw 'Evidence tag/library already exists'}
New-Item -ItemType Directory -Path $output | Out-Null
$simBin='C:/altera_lite/25.1std/questa_fse/win64'
$python='C:/Users/khanh/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
$timing='docs/verification/timing/fullrtl100_cache2/manifest.json'
$model='tests/full_rtl/build/questa25_model/manifest.json'
$rtlSources=[ordered]@{}
Get-ChildItem -LiteralPath (Join-Path $repo 'Verilog Source code') -File | Where-Object {$_.Extension -in '.sv','.v','.svh','.mem'} |
    ForEach-Object {$rtlSources[$_.Name]=(Get-FileHash -LiteralPath $_.FullName).Hash.ToLower()}
$test=Join-Path $PSScriptRoot 'host_cancel_contract.sv'
$testHash=(Get-FileHash -LiteralPath $test).Hash.ToLower()
$sourceList=Join-Path $output 'sources.f'
$rtlRoot=Join-Path $repo 'Verilog Source code'
$packages=@('npu_pkg.sv','llm_pkg.sv')
$sources=@($packages | ForEach-Object {Join-Path $rtlRoot $_})+
    @(Get-ChildItem -LiteralPath $rtlRoot -File | Where-Object {$_.Extension -in '.sv','.v' -and $_.Name -notin $packages} |
        Sort-Object Name | ForEach-Object {$_.FullName})+@($test)
$sources | ForEach-Object {'"'+$_.Replace('\','/')+'"'} | Set-Content -LiteralPath $sourceList -Encoding utf8
$relativeLibrary='tests/full_rtl/build/'+$WorkLibraryName
$relativeEvidence='tests/full_rtl/evidence/'+$EvidenceTag
$duReport=$relativeEvidence+'/design_units.json'
$commands=@()
Push-Location $repo
try {
    & $python (Join-Path $PSScriptRoot 'memory_model.py') --timing $timing --sim-bin $simBin --verify-manifest $model
    if ($LASTEXITCODE -ne 0) {throw 'RAM model integrity failed'}
    $stages=@(
        @{executable="$simBin/vlib.exe";arguments=@($library);log='vlib.log'},
        @{executable="$simBin/vlog.exe";arguments=@('-sv','-svinputport=var','-work',$library,
            ('+incdir+'+$rtlRoot),'-f',$sourceList,'-l',(Join-Path $output 'compile.log'));log='compile.console'},
        @{executable="$simBin/vsim.exe";arguments=@('-c','-onfinish','exit',('-voptargs=-duselectreport='+$duReport),
            '-L','tests/full_rtl/build/questa25_model/altera_mf_ver','-L',$relativeLibrary,'-lib',$relativeLibrary,
            '-l',(Join-Path $output 'probe.log'),'tb_host_cancel_contract','-do','run -all; quit -f');log='probe.console'}
    )
    foreach ($stage in $stages) {
        $commands+=@{executable=$stage.executable;arguments=$stage.arguments;started_utc=[DateTime]::UtcNow.ToString('o')}
        $executable=$stage.executable;$arguments=$stage.arguments
        & $executable @arguments *> (Join-Path $output $stage.log)
        if ($LASTEXITCODE -ne 0) {throw ('Probe tool failed: '+$stage.executable)}
    }
    foreach ($name in @('compile.log','probe.log')) {
        if (Select-String -LiteralPath (Join-Path $output $name) -Pattern '\*\* (Fatal|Error|Warning)|UI-Msg \(Error\)' -Quiet) {
            throw ('Probe diagnostics in '+$name)
        }
    }
    if (!(Select-String -LiteralPath (Join-Path $output 'probe.log') -Pattern 'HOST_CANCEL_CONTRACT_PASS' -Quiet)) {throw 'Probe PASS marker absent'}
    & $python (Join-Path $PSScriptRoot 'memory_model.py') --timing $timing --sim-bin $simBin --verify-manifest $model --design-units $duReport --require-memory
    if ($LASTEXITCODE -ne 0) {throw 'Actual RAM binding failed'}
    foreach ($name in $rtlSources.Keys) {
        if ((Get-FileHash -LiteralPath (Join-Path $rtlRoot $name)).Hash.ToLower() -ne $rtlSources[$name]) {throw 'RTL changed during probe'}
    }
    if ((Get-FileHash -LiteralPath $test).Hash.ToLower() -ne $testHash) {throw 'Probe changed during execution'}
    $commands | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $output 'commands.json') -Encoding utf8
    Copy-Item -LiteralPath $PSCommandPath -Destination (Join-Path $output 'runner.ps1')
    Copy-Item -LiteralPath $test -Destination (Join-Path $output 'host_cancel_contract.sv')
    $archives=[ordered]@{}
    Get-ChildItem -LiteralPath $output -File | ForEach-Object {$archives[$_.Name]=(Get-FileHash -LiteralPath $_.FullName).Hash.ToLower()}
    [ordered]@{status='PASS';completed_utc=[DateTime]::UtcNow.ToString('o');rtl_sources=$rtlSources;
        test_sha256=$testHash;archives=$archives;scope='Host cancellation and own-commit-before-ACK; actual vendor RAM; no application'} |
        ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $output 'results.json') -Encoding utf8
} finally {
    $commands | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $output 'commands.json') -Encoding utf8
    Pop-Location
}
Write-Output 'HOST_CANCEL_100MHZ_PASS'
