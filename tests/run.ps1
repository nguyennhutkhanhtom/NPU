param(
    [ValidateSet('Main','V2')][string]$Suite='Main',
    [ValidateSet('All','Host','Norm','Ternary','Rowwise','Scalar','DivProfiles','Postscale','Sigmoid','Sram','Imem','Arithmetic','AccMul','AddSub','Mul')][string]$Block='All',
    [string]$RtlDir='Verilog Source code',
    [string]$SimBin='C:\intelFPGA\20.1\modelsim_ase\win32aloem',
    [string]$Python='',
    [switch]$KeepBuild
)
# Examples: ./tests/run.ps1 -Block Norm
#           ./tests/run.ps1 -Block AccMul
# V2 is accepted as an alias for older commands; every test uses the main RTL.
$ErrorActionPreference='Stop'
if(!$Python) {
    $pythonCommand=Get-Command python.exe -ErrorAction SilentlyContinue
    $bundledPython=Join-Path $env:USERPROFILE '.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
    if($pythonCommand) {$Python=$pythonCommand.Source}
    elseif(Test-Path -LiteralPath $bundledPython) {$Python=$bundledPython}
    else {throw 'Python was not found. Pass -Python with the Python executable path.'}
}
$repo=Split-Path $PSScriptRoot
$simRoot=Join-Path $PSScriptRoot 'sim'
$results=[ordered]@{}
$sourceHashes=[ordered]@{}
$lock=$null

function Invoke-Case([string]$Library,[string]$Top,[string]$Name,[string]$Marker,[string[]]$Overrides=@()) {
    $log=Join-Path $simRoot "$Name.log"
    & "$SimBin/vsim.exe" -c -onfinish exit -l $log "$Library.$Top" @Overrides -do 'run -all; quit -f' *> "$log.console"
    if($LASTEXITCODE -ne 0 -or !(Select-String -LiteralPath $log -SimpleMatch $Marker -Quiet) -or
       (Select-String -LiteralPath $log -Pattern '^# \*\* (Fatal|Error):' -Quiet)) {
        Get-Content -LiteralPath $log -Tail 15
        throw "Test failed: $Name"
    }
    $line=(Select-String -LiteralPath $log -SimpleMatch $Marker | Select-Object -Last 1).Line
    $results[$Name]=[ordered]@{status='PASS';marker=$line;log="sim/$Name.log"}
    Write-Output $line
}

function Clear-BuildCache {
    $prefix=[IO.Path]::GetFullPath($simRoot).TrimEnd('\')+'\'
    foreach($name in @('work')) {
        $target=[IO.Path]::GetFullPath((Join-Path $simRoot $name))
        if(!$target.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) {throw "Invalid build path: $target"}
        if(Test-Path -LiteralPath $target) {Remove-Item -LiteralPath $target -Recurse -Force}
    }
    foreach($name in @('sources.f','host_vectors.txt','sigmoid_expected.mem','vectors.json')) {
        $target=Join-Path $simRoot $name
        if(Test-Path -LiteralPath $target) {Remove-Item -LiteralPath $target}
    }
    Get-ChildItem -LiteralPath $simRoot -Filter '*.console' -File | ForEach-Object {Remove-Item -LiteralPath $_.FullName}
}

Push-Location $repo
try {
    New-Item -ItemType Directory -Force $simRoot | Out-Null
    $lock=[IO.File]::Open((Join-Path $simRoot '.run.lock'),'OpenOrCreate','ReadWrite','None')
    $rtlPath=(Resolve-Path -LiteralPath $RtlDir).Path
    $rtl=@(Get-Item -LiteralPath (Join-Path $rtlPath 'npu_pkg.sv'))+
         @(Get-ChildItem -LiteralPath $rtlPath -File | Where-Object {$_.Extension -in '.sv','.v' -and $_.Name -ne 'npu_pkg.sv'} | Sort-Object Name)
    foreach($file in Get-ChildItem -LiteralPath $rtlPath -File | Where-Object {$_.Extension -in '.sv','.v','.svh','.mem'}) {
        $sourceHashes[$file.Name]=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLower()
    }
    & $Python (Join-Path $PSScriptRoot 'reference.py') --rtl $rtlPath --block $Block *> (Join-Path $simRoot 'reference.log')
    if($LASTEXITCODE -ne 0) {Get-Content (Join-Path $simRoot 'reference.log') -Tail 15;throw 'Reference generation or LUT verification failed'}
    $vectors=Get-Content -LiteralPath (Join-Path $simRoot 'vectors.json') -Raw | ConvertFrom-Json
    $romMarker=(Select-String -LiteralPath (Join-Path $simRoot 'reference.log') -SimpleMatch 'ROM_VALIDATION_PASS:' | Select-Object -Last 1).Line
    if(!$romMarker) {throw 'ROM validation result is missing'}
    $results['rom-validation']=[ordered]@{status='PASS';marker=$romMarker;log='sim/reference.log'}
    Write-Output $romMarker
    $sources=@($rtl | ForEach-Object {'"'+$_.FullName.Replace('\','/')+'"'})+
             @('"'+(Join-Path $PSScriptRoot 'tb_all.sv').Replace('\','/')+'"')
    $sourceList=Join-Path $simRoot 'sources.f'
    $sources | Set-Content -LiteralPath $sourceList -Encoding utf8
    $names=switch($Block) {
        'All'        {@('host','scalar','divprofiles','postscale','sigmoid','arithmetic','imem','sram')}
        {$_ -in @('Host','Norm','Ternary','Rowwise')} {@('host')}
        {$_ -in @('Arithmetic','AccMul','AddSub','Mul')} {@('arithmetic')}
        default      {@($Block.ToLower())}
    }
    $library='tests/sim/work'
    if(!(Test-Path -LiteralPath $library)) {
        & "$SimBin/vlib.exe" $library *> (Join-Path $simRoot 'vlib.log')
        if($LASTEXITCODE -ne 0) {throw 'Cannot create simulation library'}
    }
    $compileLog=Join-Path $simRoot 'compile.log'
    & "$SimBin/vlog.exe" -sv -svinputport=var -work $library "+incdir+$rtlPath" -f $sourceList -l $compileLog *> "$compileLog.console"
    if($LASTEXITCODE -ne 0 -or !(Select-String -LiteralPath $compileLog -SimpleMatch 'Errors: 0' -Quiet)) {
        Get-Content -LiteralPath $compileLog -Tail 20
        throw 'RTL compilation failed'
    }
    foreach($name in $names) {
        $overrides=if($name -eq 'arithmetic' -and $Block -in @('AccMul','AddSub','Mul')) {@("-gBLOCK=$($Block.ToLower())")} else {@()}
        Invoke-Case $library "tb_$name" $name ($name.ToUpper()+'_PASS') $overrides
    }
    $testHashes=[ordered]@{}
    foreach($name in @('tb_all.sv','reference.py','run.ps1')) {
        $testHashes[$name]=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $name)).Hash.ToLower()
    }
    [ordered]@{status='PASS';verified_utc=[DateTime]::UtcNow.ToString('o');block=$Block;rtl=$rtlPath;
        vectors=$vectors;tests=$results;rtl_sources=$sourceHashes;test_sources=$testHashes} |
        ConvertTo-Json -Depth 8 | ForEach-Object {
            [IO.File]::WriteAllText((Join-Path $PSScriptRoot 'results.json'),$_.Replace([string][char]13,'')+"`n",[Text.UTF8Encoding]::new($false))
        }
    if(!$KeepBuild) {Clear-BuildCache}
    Write-Output "MAIN_TESTS_PASS: block=$Block tests=$($results.Count)"
} catch {
    [ordered]@{status='FAIL';verified_utc=[DateTime]::UtcNow.ToString('o');block=$Block;error=$_.Exception.Message;
        tests=$results;rtl_sources=$sourceHashes} | ConvertTo-Json -Depth 8 |
        ForEach-Object {
            [IO.File]::WriteAllText((Join-Path $PSScriptRoot 'results.json'),$_.Replace([string][char]13,'')+"`n",[Text.UTF8Encoding]::new($false))
        }
    throw
} finally {
    if($null -ne $lock) {$lock.Dispose()}
    Pop-Location
}
