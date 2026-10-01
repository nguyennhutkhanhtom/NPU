param([string]$Python='')
$ErrorActionPreference='Stop'
if(!$Python) {
    $pythonCommand=Get-Command python.exe -ErrorAction SilentlyContinue
    $bundledPython=Join-Path $env:USERPROFILE '.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
    if($pythonCommand) {$Python=$pythonCommand.Source}
    elseif(Test-Path -LiteralPath $bundledPython) {$Python=$bundledPython}
    else {throw 'Python was not found. Pass -Python with a Python 3.11 or 3.12 executable.'}
}
& $Python -c "import sys; assert (3,11)<=sys.version_info[:2]<=(3,12), 'Use Python 3.11 or 3.12 for the pinned PyTorch 2.5.1 and NumPy runtime'"
if($LASTEXITCODE -ne 0) {throw 'Unsupported Python version for pinned dependencies'}
& $Python -m pip install --upgrade --target (Join-Path $PSScriptRoot 'packages') --index-url https://download.pytorch.org/whl/cpu torch==2.5.1+cpu
if($LASTEXITCODE -ne 0) {throw 'Scoped CPU PyTorch installation failed'}
& $Python -m pip install --upgrade --target (Join-Path $PSScriptRoot 'packages') -r (Join-Path $PSScriptRoot 'requirements.txt')
if($LASTEXITCODE -ne 0) {throw 'Scoped tokenizer and checkpoint dependencies failed'}
& $Python (Join-Path $PSScriptRoot 'fetch_assets.py')
if($LASTEXITCODE -ne 0) {throw 'Pinned asset download/verification failed'}
