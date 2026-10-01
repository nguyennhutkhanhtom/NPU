param(
    [string]$Python='',
    [string]$SimBin='C:/intelFPGA/20.1/modelsim_ase/win32aloem'
)
$ErrorActionPreference='Stop'
if(!$Python) {
    $pythonCommand=Get-Command python.exe -ErrorAction SilentlyContinue
    $bundledPython=Join-Path $env:USERPROFILE '.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
    if($pythonCommand) {$Python=$pythonCommand.Source}
    elseif(Test-Path -LiteralPath $bundledPython) {$Python=$bundledPython}
    else {throw 'Python was not found. Pass -Python with the Python executable path.'}
}
$previousPythonPath=$env:PYTHONPATH
$scopedPackages=Join-Path $PSScriptRoot 'packages'
$env:PYTHONPATH=if($previousPythonPath) {$scopedPackages+[IO.Path]::PathSeparator+$previousPythonPath} else {$scopedPackages}
$repo=Split-Path (Split-Path $PSScriptRoot)
Push-Location $repo
try {
    & $Python (Join-Path $PSScriptRoot 'fetch_assets.py') --check
    if($LASTEXITCODE -ne 0) {throw 'Demo assets are missing or changed. Run tests/model_demo/setup.ps1 first.'}
    & $Python (Join-Path $PSScriptRoot 'export_demo.py') *> (Join-Path $PSScriptRoot 'export.log')
    if($LASTEXITCODE -ne 0) {Get-Content (Join-Path $PSScriptRoot 'export.log') -Tail 15;throw 'Model export failed'}
    Get-Content (Join-Path $PSScriptRoot 'export.log')
    $rtlDir=Join-Path $repo 'Verilog Source code'
    $sources=@(Get-Item -LiteralPath (Join-Path $rtlDir 'npu_pkg.sv'))+
        @(Get-ChildItem -LiteralPath $rtlDir -File | Where-Object {$_.Extension -in '.sv','.v' -and $_.Name -ne 'npu_pkg.sv'} | Sort-Object Name)
    $lines=@($sources | ForEach-Object {'"'+$_.FullName.Replace('\','/')+'"'})+
        @('"'+(Join-Path $PSScriptRoot 'tb_model_demo.sv').Replace('\','/')+'"')
    $sourceList=Join-Path $PSScriptRoot 'sources.f'
    $lines | Set-Content -LiteralPath $sourceList -Encoding utf8
    $library='tests/model_demo/work'
    if(!(Test-Path -LiteralPath $library)) {
        & "$SimBin/vlib.exe" $library *> (Join-Path $PSScriptRoot 'vlib.log')
        if($LASTEXITCODE -ne 0) {throw 'Cannot create demo library'}
    }
    & "$SimBin/vlog.exe" -sv -svinputport=var -work $library "+incdir+$rtlDir" -f $sourceList -l (Join-Path $PSScriptRoot 'compile.log') *> (Join-Path $PSScriptRoot 'compile.console')
    if($LASTEXITCODE -ne 0 -or !(Select-String -LiteralPath (Join-Path $PSScriptRoot 'compile.log') -SimpleMatch 'Errors: 0, Warnings: 0' -Quiet)) {Get-Content (Join-Path $PSScriptRoot 'compile.log') -Tail 15;throw 'Demo compile failed'}
    & "$SimBin/vsim.exe" -c -onfinish exit -l (Join-Path $PSScriptRoot 'model_demo.log') "$library.tb_model_demo" -do 'run -all; quit -f' *> (Join-Path $PSScriptRoot 'model_demo.console')
    $simExit=$LASTEXITCODE
    Get-Content (Join-Path $PSScriptRoot 'model_demo.log') -Tail 14
    if($simExit -ne 0 -or !(Select-String -LiteralPath (Join-Path $PSScriptRoot 'model_demo.log') -SimpleMatch 'MODEL_DEMO_PASS' -Quiet) -or
       (Select-String -LiteralPath (Join-Path $PSScriptRoot 'model_demo.log') -Pattern '^# \*\* (Fatal|Error)' -Quiet)) {throw 'Model RTL demo failed'}
    & $Python (Join-Path $PSScriptRoot 'finalize.py')
    if($LASTEXITCODE -ne 0) {throw 'Model result validation failed'}
} finally {
    $env:PYTHONPATH=$previousPythonPath
    Pop-Location
}
