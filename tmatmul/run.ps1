param([string]$SimBin='C:\intelFPGA\20.1\modelsim_ase\win32aloem')
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot
$sim=Join-Path $PSScriptRoot 'sim'
$results=[ordered]@{}
$runLock=$null
function Invoke-Test([string]$Top,[string]$Name,[string]$Marker,[string[]]$Overrides=@()) {
    & "$SimBin/vsim.exe" -c -onfinish exit -l "$Name.log" "work.$Top" @Overrides -do 'run -all; quit -f' *> "$Name.console"
    if($LASTEXITCODE -ne 0 -or !(Select-String -LiteralPath "$Name.log" -SimpleMatch $Marker -Quiet) -or
        (Select-String -LiteralPath "$Name.log" -Pattern '^# \*\* (Fatal|Error):' -Quiet)) {
        Get-Content -LiteralPath "$Name.log" -Tail 25
        throw "Test failed: $Name"
    }
    $pass=(Select-String -LiteralPath "$Name.log" -SimpleMatch $Marker | Select-Object -Last 1).Line
    $results[$Name]=[ordered]@{status='PASS';marker=$pass;log="sim/$Name.log"}
    Write-Output $pass
}
Push-Location $sim
try {
    $runLock=[IO.File]::Open((Join-Path $sim '.run.lock'),'OpenOrCreate','ReadWrite','None')
    if(!(Test-Path work)) {
        & "$SimBin/vlib.exe" work *> create.log
        if($LASTEXITCODE -ne 0) {throw 'Cannot create simulation library'}
    }
    $rtl=@(Get-ChildItem -LiteralPath (Join-Path $repo 'Verilog Source code') -File | Where-Object {$_.Extension -in '.sv','.v'})
    $tests=@(Get-ChildItem -LiteralPath $sim -Filter 'tb_*.sv' -File)
    $lines=@($rtl | ForEach-Object {'"../../Verilog Source code/'+$_.Name+'"'})
    $lines+=@($tests | ForEach-Object {$_.Name})
    $lines | Set-Content -LiteralPath sources.f -Encoding ascii
    & "$SimBin/vlog.exe" -sv -work work -f sources.f *> compile.log
    if($LASTEXITCODE -ne 0 -or !(Select-String -LiteralPath compile.log -SimpleMatch 'Errors: 0' -Quiet)) {
        Get-Content compile.log -Tail 25
        throw 'RTL compilation failed'
    }
    # Structural fixtures for inactive legacy ALU tables; no EXP/SIG accuracy claim.
    [IO.File]::WriteAllLines((Join-Path $sim 'instruction.mem'),[string[]](@('1111111111111')*512))
    [IO.File]::WriteAllLines((Join-Path $sim 'sigContent.mif'),[string[]](@('0000000000000000')*1024))
    [IO.File]::WriteAllLines((Join-Path $sim 'exp_content.mif'),[string[]](@('0000')*512))
    # The real core also instantiates NORM, even in TMATMUL-only programs.
    New-Item -ItemType Directory -Force (Join-Path $sim 'data') | Out-Null
    Copy-Item -LiteralPath (Join-Path $repo 'data/normContent.mif') -Destination (Join-Path $sim 'data/normContent.mif')
    foreach($n in @(1,2,3,4,5,7,8,17,31,32,33,127,512)) {
        Invoke-Test tb_acc_mul "acc-8-$n" 'ACC_PASS' @('-gW=8',"-gN=$n")
    }
    foreach($w in @(1,4,16,24,32)) {
        Invoke-Test tb_acc_mul "acc-$w-37" 'ACC_PASS' @("-gW=$w",'-gN=37')
    }
    Invoke-Test tb_acc_mul 'acc-wrap' 'ACC_PASS' @('-gW=16','-gN=512','-gA=16')
    foreach($sat in @(0,1)) {
        Invoke-Test tb_exhaustive "exhaustive-$sat" 'EXHAUSTIVE_PASS' @("-gSAT=$sat")
        foreach($w in @(8,16)) {
            Invoke-Test tb_ternary "matrix-$w-$sat" 'TERNARY_PASS' @("-gW=$w","-gSAT=$sat")
        }
    }
    $profiles=@(
        @{Name='one-bit';Args=@('-gW=1','-gL=4','-gR=1','-gC=4','-gD=1','-gG=1')},
        @{Name='single';Args=@('-gW=4','-gL=1','-gR=1','-gC=1','-gD=1','-gG=1')},
        @{Name='odd-width';Args=@('-gW=7','-gR=37','-gC=96','-gD=16','-gG=5')},
        @{Name='non-power';Args=@('-gW=12','-gL=6','-gR=13','-gC=18','-gD=3','-gG=2')},
        @{Name='partial';Args=@('-gW=24','-gL=16','-gR=35','-gC=48','-gD=8','-gG=3')},
        @{Name='wide';Args=@('-gW=32','-gL=32','-gR=33','-gC=64','-gD=32','-gG=4')}
    )
    foreach($profile in $profiles) {Invoke-Test tb_ternary $profile.Name 'TERNARY_PASS' $profile.Args}
    foreach($w in @(8,12,16)) {Invoke-Test tb_memory "memory-$w" 'MEMORY_PASS' @("-gW=$w")}
    Invoke-Test tb_core 'core' 'CORE_PASS'
    $hashes=[ordered]@{}
    foreach($file in @($rtl)+@($tests)+@(Get-Item -LiteralPath $PSCommandPath)) {
        $hashes[$file.FullName.Substring($repo.Length+1).Replace('\','/')]=(Get-FileHash -LiteralPath $file.FullName).Hash.ToLower()
    }
    [ordered]@{
        status='PASS';generated_utc=[DateTime]::UtcNow.ToString('o');
        scope='Ternary arithmetic, streaming memory and TMATMUL processor integration';
        simulator='ModelSim 2020.1 (RTL simulation only)';tests=$results;sources=$hashes;
        asic_synthesis_run=$false;measured_fmax_mhz=$null;measured_area=$null
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'verification.json') -Encoding utf8
} finally {
    if($null -ne $runLock) {$runLock.Dispose()}
    Pop-Location
}
