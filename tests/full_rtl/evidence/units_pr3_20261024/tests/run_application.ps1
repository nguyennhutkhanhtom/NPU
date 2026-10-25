param(
    [Parameter(Mandatory=$true)][string]$TimingManifest,
    [switch]$SkipGate,
    [string]$Python='C:/Users/khanh/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe',
    [string]$SimBin='C:/altera_lite/25.1std/questa_fse/win64',
    [bool]$Questa=$true,
    [string]$MemoryModelDir='tests/full_rtl/build/application_memory_model',
    [string]$Prompt='Once upon a time, Lily found a tiny kitten.',
    [int]$NewTokens=96,[int]$Temperature=166,[int]$Seed=7,[int]$MinNew=64
)
$ErrorActionPreference='Stop'
$repo=Split-Path (Split-Path $PSScriptRoot)
Push-Location $repo
try {
    if ($SkipGate) {
        Write-Warning 'Hardware gate skipped: functional token matching only; timing and unit status are not verified.'
    } else {
        & $Python (Join-Path $PSScriptRoot 'check_gate.py') $TimingManifest
        if($LASTEXITCODE -ne 0) {throw 'Application blocked: synthesis/timing/unit gate has not passed'}
    }
    $memoryModel=if ([IO.Path]::IsPathRooted($MemoryModelDir)) {$MemoryModelDir} else {Join-Path $repo $MemoryModelDir}
    & $Python (Join-Path $PSScriptRoot 'memory_model.py') --timing $TimingManifest --sim-bin $SimBin --output $memoryModel
    if($LASTEXITCODE -ne 0) {throw 'RAM model does not match the recorded Quartus installation'}
    $memoryManifest=Join-Path $memoryModel 'manifest.json'
    $memoryLibrary=(Get-Content -LiteralPath $memoryManifest -Raw | ConvertFrom-Json).library
    $bindingReport='tests/full_rtl/build/application_design_units.json'
    $exportArguments=@('--timing',$TimingManifest,'--memory-model',$memoryManifest,'--prompt',$Prompt,'--new-tokens',$NewTokens,'--temperature',$Temperature,'--seed',$Seed,'--min-new',$MinNew)
    if ($SkipGate) {$exportArguments+='--skip-gate'}
    if ($Questa) {$exportArguments+=@('--design-units',$bindingReport)}
    & $Python (Join-Path $PSScriptRoot 'export_checkpoint.py') @exportArguments
    if($LASTEXITCODE -ne 0) {throw 'Application export/reference failed'}
    $build=Join-Path $PSScriptRoot 'build'
    $rtl=Join-Path $repo 'Verilog Source code'
    $packages=@('npu_pkg.sv','llm_pkg.sv')
    $sources=@($packages | ForEach-Object {Join-Path $rtl $_})+
        @(Get-ChildItem -LiteralPath $rtl -File | Where-Object {$_.Extension -in '.sv','.v' -and $_.Name -notin $packages} | Sort-Object Name | ForEach-Object {$_.FullName})+
        @((Join-Path $PSScriptRoot 'application_tb.sv'))
    $list=Join-Path $build 'application_sources.f'
    # Windows PowerShell's UTF-8 BOM becomes part of vlog's first filename.
    $sourceLines=@($sources | ForEach-Object {'"'+$_.Replace('\','/')+'"'})
    [IO.File]::WriteAllLines($list, $sourceLines, [Text.UTF8Encoding]::new($false))
    $library=Join-Path $build 'application_work'
    & "$SimBin/vlib.exe" $library *> (Join-Path $build 'application_vlib.log')
    if($LASTEXITCODE -ne 0) {throw 'Cannot create application library'}
    & "$SimBin/vlog.exe" -sv -svinputport=var -work $library "+incdir+$rtl" "+incdir+$build" -f $list -l (Join-Path $build 'application_compile.log') *> (Join-Path $build 'application_compile.console')
    if($LASTEXITCODE -ne 0) {
        Get-Content -LiteralPath (Join-Path $build 'application_compile.log') -Tail 20
        throw 'Application compile failed'
    }
    $log=Join-Path $build 'application.log'
    $simArguments=@('-c','-onfinish','exit')
    $simulationLibrary=$library
    $simulationMemory=$memoryLibrary
    if ($Questa) {
        $simulationLibrary='tests/full_rtl/build/application_work'
        # URI relative paths also work on Windows PowerShell's .NET Framework.
        $repoUri=[Uri]::new($repo+[IO.Path]::DirectorySeparatorChar)
        $memoryUri=[Uri]::new([IO.Path]::GetFullPath($memoryLibrary))
        $simulationMemory=[Uri]::UnescapeDataString($repoUri.MakeRelativeUri($memoryUri).ToString())
    }
    if ($Questa) {$simArguments+='-voptargs=-duselectreport='+$bindingReport}
    $simArguments+=@('-L',$simulationMemory,'-L',$simulationLibrary,'-lib',$simulationLibrary,'-l',$log,'tb_full_rtl_application','-do','run -all; quit -f')
    & "$SimBin/vsim.exe" @simArguments *> "$log.console"
    if($LASTEXITCODE -ne 0 -or !(Select-String -LiteralPath $log -SimpleMatch 'FULL_RTL_APPLICATION_PASS' -Quiet) -or (Select-String -LiteralPath $log -Pattern '^# \*\* (Fatal|Error)' -Quiet)) {
        Get-Content -LiteralPath $log -Tail 20;throw 'Application failed'
    }
    $finalizeArguments=@('--timing',$TimingManifest)
    if ($SkipGate) {$finalizeArguments+='--skip-gate'}
    & $Python (Join-Path $PSScriptRoot 'finalize_application.py') @finalizeArguments
    if($LASTEXITCODE -ne 0) {throw 'Application evidence failed'}
} finally {Pop-Location}
