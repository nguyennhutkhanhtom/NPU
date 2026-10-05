param(
    [string]$Project='quartus/matmul_free',
    [string]$RtlDir='Verilog Source code',
    [ValidatePattern('^[a-z][a-z0-9_-]{0,63}$')][string]$Tag='optimized',
    [string]$QuartusBin='',
    [string]$Python='',
    [ValidateRange(1,1000)][int]$ReportPathCount=40
)
$ErrorActionPreference='Stop'
$repo=Split-Path (Split-Path $PSScriptRoot)
function Resolve-RepoPath([string]$Path) {
    if([IO.Path]::IsPathRooted($Path)) {return [IO.Path]::GetFullPath($Path)}
    return [IO.Path]::GetFullPath((Join-Path $repo $Path))
}
if(!$Python) {
    $pythonCommand=Get-Command python.exe -ErrorAction SilentlyContinue
    $bundledPython=Join-Path $env:USERPROFILE '.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
    if($pythonCommand) {$Python=$pythonCommand.Source}
    elseif(Test-Path -LiteralPath $bundledPython) {$Python=$bundledPython}
    else {throw 'Python was not found. Pass -Python with its executable path.'}
}
if(!$QuartusBin) {
    $quartusCommand=Get-Command quartus_map.exe -ErrorAction SilentlyContinue
    if($quartusCommand) {$QuartusBin=Split-Path $quartusCommand.Source}
    else {throw 'Quartus was not found on PATH. Pass -QuartusBin with its bin64 directory.'}
}
$projectPath=Resolve-RepoPath $Project
if([IO.Path]::GetExtension($projectPath) -in @('.qpf','.qsf')) {$projectPath=[IO.Path]::ChangeExtension($projectPath,$null)}
$rtlPath=Resolve-RepoPath $RtlDir
$outputPath=Join-Path $repo "docs/verification/timing/$Tag"
$revision=Split-Path $projectPath -Leaf
$record=Join-Path $PSScriptRoot 'record.py'
$extract=Join-Path $PSScriptRoot 'extract.tcl'
foreach($executable in @('quartus_map.exe','quartus_fit.exe','quartus_sta.exe')) {
    if(!(Test-Path -LiteralPath (Join-Path $QuartusBin $executable))) {throw "Missing Quartus executable: $executable"}
}
if(!(Test-Path -LiteralPath ($projectPath+'.qpf'))) {throw "Missing project: $projectPath.qpf"}
if((Test-Path -LiteralPath $outputPath) -and (Get-ChildItem -LiteralPath $outputPath -File -Recurse | Select-Object -First 1)) {
    throw "Timing tag already contains evidence: $Tag. Choose a new -Tag to preserve the earlier reports."
}
New-Item -ItemType Directory -Path $outputPath -Force | Out-Null
& $Python $record --project $projectPath --rtl-dir $rtlPath --output $outputPath --snapshot-only
if($LASTEXITCODE -ne 0) {throw 'Timing input snapshot failed.'}
$commands=@()
function Invoke-TimingStage([string]$Name,[string]$Executable,[string[]]$Arguments) {
    $log=Join-Path $outputPath "$Name.log"
    $stageStarted=[DateTime]::UtcNow
    $script:commands+=@{stage=$Name;executable=$Executable;arguments=$Arguments;started_at_utc=$stageStarted.ToString('o')}
    Write-Output "TIMING_STAGE_START: $Name"
    & $Executable @Arguments *> $log
    $stageExitCode=$LASTEXITCODE
    if($stageExitCode -ne 0) {
        Get-Content -LiteralPath $log -Tail 25
        throw "Timing stage failed: $Name (exit $stageExitCode)"
    }
    $successPattern=switch($Name) {
        'map' {'Quartus Prime Analysis & Synthesis was successful\. 0 errors'}
        'fit' {'Quartus Prime Fitter was successful\. 0 errors'}
        'sta' {'Quartus Prime Timing Analyzer was successful\. 0 errors'}
        'extract' {'TIMING_EXTRACTION_PASS:'}
    }
    if(!(Select-String -LiteralPath $log -Pattern $successPattern -Quiet)) {
        Get-Content -LiteralPath $log -Tail 25
        throw "Timing stage did not report successful completion: $Name"
    }
    if($Name -in @('map','fit','sta')) {
        foreach($suffix in @('rpt','summary')) {
            $stageReport=Join-Path (Split-Path $projectPath) "output_files/$revision.$Name.$suffix"
            if(!(Test-Path -LiteralPath $stageReport) -or
               (Get-Item -LiteralPath $stageReport).LastWriteTimeUtc -lt $stageStarted) {
                throw "Timing stage did not produce a fresh report: $stageReport"
            }
        }
    }
    Write-Output "TIMING_STAGE_PASS: $Name"
}
Push-Location (Split-Path $projectPath)
try {
    foreach($stage in @('map','fit')) {
        Invoke-TimingStage $stage (Join-Path $QuartusBin "quartus_$stage.exe") @('--read_settings_files=on','--write_settings_files=off',$revision,'-c',$revision)
    }
    # Quartus 18.1 STA does not accept map/fit's write_settings_files option.
    Invoke-TimingStage 'sta' (Join-Path $QuartusBin 'quartus_sta.exe') @($revision,'-c',$revision)
} finally {
    Pop-Location
}
Invoke-TimingStage 'extract' (Join-Path $QuartusBin 'quartus_sta.exe') @('-t',$extract,$outputPath,'sdc',$projectPath,[string]$ReportPathCount)
$commands | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $outputPath 'commands.json') -Encoding utf8
& $Python $record --project $projectPath --rtl-dir $rtlPath --output $outputPath
if($LASTEXITCODE -ne 0) {throw 'Timing evidence record failed; compilation inputs may have changed.'}
