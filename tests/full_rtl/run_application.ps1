param(
    [Parameter(Mandatory=$true)][string]$TimingManifest,
    [string]$Python='C:/Users/khanh/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe',
    [string]$SimBin='C:/intelFPGA/20.1/modelsim_ase/win32aloem',
    [string]$Prompt='Once upon a time, Lily found a tiny kitten.',
    [int]$NewTokens=96,[int]$Temperature=166,[int]$Seed=7,[int]$MinNew=64
)
$ErrorActionPreference='Stop'
$repo=Split-Path (Split-Path $PSScriptRoot)
Push-Location $repo
try {
    # Both entry points reject missing, stale or failing 100 MHz evidence.
    & $Python (Join-Path $PSScriptRoot 'check_gate.py') $TimingManifest
    if($LASTEXITCODE -ne 0) {throw 'Application blocked: synthesis/timing/unit gate has not passed'}
    & $Python (Join-Path $PSScriptRoot 'export_checkpoint.py') --timing $TimingManifest --prompt $Prompt --new-tokens $NewTokens --temperature $Temperature --seed $Seed --min-new $MinNew
    if($LASTEXITCODE -ne 0) {throw 'Application export/reference failed'}
    $build=Join-Path $PSScriptRoot 'build'
    $rtl=Join-Path $repo 'Verilog Source code'
    $packages=@('npu_pkg.sv','llm_pkg.sv')
    $sources=@($packages | ForEach-Object {Join-Path $rtl $_})+
        @(Get-ChildItem -LiteralPath $rtl -File | Where-Object {$_.Extension -in '.sv','.v' -and $_.Name -notin $packages} | Sort-Object Name | ForEach-Object {$_.FullName})+
        @((Join-Path $PSScriptRoot 'application_tb.sv'))
    $list=Join-Path $build 'application_sources.f'
    $sources | ForEach-Object {'"'+$_.Replace('\','/')+'"'} | Set-Content -LiteralPath $list -Encoding utf8
    $library=Join-Path $build 'application_work'
    & "$SimBin/vlib.exe" $library *> (Join-Path $build 'application_vlib.log')
    if($LASTEXITCODE -ne 0) {throw 'Cannot create application library'}
    & "$SimBin/vlog.exe" -sv -svinputport=var -work $library "+incdir+$rtl" "+incdir+$build" -f $list -l (Join-Path $build 'application_compile.log') *> (Join-Path $build 'application_compile.console')
    if($LASTEXITCODE -ne 0) {throw 'Application compile failed'}
    $log=Join-Path $build 'application.log'
    & "$SimBin/vsim.exe" -c -onfinish exit -L $library -lib $library -l $log tb_full_rtl_application -do 'run -all; quit -f' *> "$log.console"
    if($LASTEXITCODE -ne 0 -or !(Select-String -LiteralPath $log -SimpleMatch 'FULL_RTL_APPLICATION_PASS' -Quiet) -or (Select-String -LiteralPath $log -Pattern '^# \*\* (Fatal|Error)' -Quiet)) {
        Get-Content -LiteralPath $log -Tail 20;throw 'Application failed'
    }
    & $Python (Join-Path $PSScriptRoot 'finalize_application.py') --timing $TimingManifest
    if($LASTEXITCODE -ne 0) {throw 'Application evidence failed'}
} finally {Pop-Location}
