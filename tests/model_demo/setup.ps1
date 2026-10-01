param(
    [string]$Python='',
    [switch]$SkipPackages
)
$ErrorActionPreference='Stop'
if(!$Python) {
    $pythonCommand=Get-Command python.exe -ErrorAction SilentlyContinue
    $bundledPython=Join-Path $env:USERPROFILE '.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
    if($pythonCommand) {$Python=$pythonCommand.Source}
    elseif(Test-Path -LiteralPath $bundledPython) {$Python=$bundledPython}
    else {throw 'Python was not found. Pass -Python with the Python executable path.'}
}
$packages=Join-Path $PSScriptRoot 'packages'
if(!$SkipPackages) {
    & $Python -m pip install --target $packages --upgrade --index-url https://download.pytorch.org/whl/cpu 'torch==2.5.1+cpu'
    if($LASTEXITCODE -ne 0) {throw 'CPU PyTorch installation failed'}
    & $Python -m pip install --target $packages --upgrade 'numpy==2.3.5' 'Pillow==12.3.0'
    if($LASTEXITCODE -ne 0) {throw 'Demo array/image dependency installation failed'}
}
& $Python (Join-Path $PSScriptRoot 'fetch_assets.py')
if($LASTEXITCODE -ne 0) {throw 'Pinned asset download or validation failed'}
$previousPythonPath=$env:PYTHONPATH
$env:PYTHONPATH=if($previousPythonPath) {$packages+[IO.Path]::PathSeparator+$previousPythonPath} else {$packages}
try {
    @'
import torch, numpy, PIL
assert torch.__version__ == "2.5.1+cpu"
print("MNIST_SETUP_PASS", torch.__version__, numpy.__version__, PIL.__version__)
'@ | & $Python -
    if($LASTEXITCODE -ne 0) {throw 'Demo runtime verification failed'}
} finally {
    $env:PYTHONPATH=$previousPythonPath
}
