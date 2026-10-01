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
    & $Python -c "import sys; assert (3,11)<=sys.version_info[:2]<=(3,12), 'Use Python 3.11 or 3.12 for pinned demo dependencies'"
    if($LASTEXITCODE -ne 0) {throw 'Unsupported Python version. Pass -Python with Python 3.11 or 3.12.'}
    & $Python (Join-Path $PSScriptRoot 'fetch_assets.py') --check
    if($LASTEXITCODE -ne 0) {throw 'Demo assets are missing or changed. Run tests/language_demo/setup.ps1 first.'}
    & $Python (Join-Path $PSScriptRoot 'export_demo.py') *> (Join-Path $PSScriptRoot 'export.log')
    if($LASTEXITCODE -ne 0) {Get-Content (Join-Path $PSScriptRoot 'export.log') -Tail 15;throw 'Language export failed'}
    Get-Content (Join-Path $PSScriptRoot 'export.log')
    $rtlDir=Join-Path $repo 'Verilog Source code'
    $sources=@(Get-Item -LiteralPath (Join-Path $rtlDir 'npu_pkg.sv'))+
        @(Get-ChildItem -LiteralPath $rtlDir -File | Where-Object {$_.Extension -in '.sv','.v' -and $_.Name -ne 'npu_pkg.sv'} | Sort-Object Name)
    $lines=@($sources | ForEach-Object {'"'+$_.FullName.Replace('\','/')+'"'})+
        @('"'+(Join-Path $PSScriptRoot 'tb_language_demo.sv').Replace('\','/')+'"')
    $sourceList=Join-Path $PSScriptRoot 'sources.f'
    $lines | Set-Content -LiteralPath $sourceList -Encoding utf8
    $library='tests/language_demo/work'
    if(!(Test-Path -LiteralPath $library)) {
        & "$SimBin/vlib.exe" $library *> (Join-Path $PSScriptRoot 'vlib.log')
        if($LASTEXITCODE -ne 0) {throw 'Cannot create demo library'}
    }
    & "$SimBin/vlog.exe" -sv -svinputport=var -work $library "+incdir+$rtlDir" -f $sourceList -l (Join-Path $PSScriptRoot 'compile.log') *> (Join-Path $PSScriptRoot 'compile.console')
    if($LASTEXITCODE -ne 0 -or !(Select-String -LiteralPath (Join-Path $PSScriptRoot 'compile.log') -SimpleMatch 'Errors: 0, Warnings: 0' -Quiet)) {Get-Content (Join-Path $PSScriptRoot 'compile.log') -Tail 15;throw 'Demo compile failed'}
    & "$SimBin/vsim.exe" -c -onfinish exit -l (Join-Path $PSScriptRoot 'language_demo.log') "$library.tb_language_demo" -do 'run -all; quit -f' *> (Join-Path $PSScriptRoot 'language_demo.console')
    $simExit=$LASTEXITCODE
    Get-Content (Join-Path $PSScriptRoot 'language_demo.log') -Tail 14
    if($simExit -ne 0 -or !(Select-String -LiteralPath (Join-Path $PSScriptRoot 'language_demo.log') -SimpleMatch 'LANGUAGE_DEMO_PASS' -Quiet) -or
       (Select-String -LiteralPath (Join-Path $PSScriptRoot 'language_demo.log') -Pattern '^# \*\* (Fatal|Error)' -Quiet)) {throw 'Language RTL demo failed'}
    & $Python (Join-Path $PSScriptRoot 'finalize.py')
    if($LASTEXITCODE -ne 0) {throw 'Language result validation failed'}
} finally {
    $env:PYTHONPATH=$previousPythonPath
    Pop-Location
}
