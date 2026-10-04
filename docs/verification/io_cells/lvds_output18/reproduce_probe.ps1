$ErrorActionPreference='Stop'
$root=Join-Path $PSScriptRoot 'io_probe4'
if(Test-Path -LiteralPath $root) {throw 'Preserve prior probe evidence; directory already exists'}
$bin='C:/intelFPGA_lite/18.1/quartus/bin64'
$extract=Join-Path (Get-Location) 'tools/timing/extract.tcl'
$cases=,@('lvds','LVDS')
foreach($case in $cases) {
    $folder=Join-Path $root $case[0]
    New-Item -ItemType Directory -Path $folder | Out-Null
    @'
module io_probe(input logic clk,input logic [7:0] d,output logic [7:0] q);
    always_ff @(posedge clk) q <= d;
endmodule
'@ | Set-Content -LiteralPath (Join-Path $folder 'io_probe.sv') -Encoding ascii
    'PROJECT_REVISION = "io_probe"' | Set-Content -LiteralPath (Join-Path $folder 'io_probe.qpf') -Encoding ascii
    $settings=@('set_global_assignment -name FAMILY "Cyclone V"',
        'set_global_assignment -name DEVICE 5CGXFC9E6F35C7',
        'set_global_assignment -name TOP_LEVEL_ENTITY io_probe',
        'set_global_assignment -name PROJECT_OUTPUT_DIRECTORY output_files',
        'set_global_assignment -name SYSTEMVERILOG_FILE io_probe.sv',
        'set_global_assignment -name SDC_FILE io_probe.sdc',
        'set_global_assignment -name MIN_CORE_JUNCTION_TEMP 0',
        'set_global_assignment -name MAX_CORE_JUNCTION_TEMP 85',
        'set_global_assignment -name AUTO_DSP_RECOGNITION OFF',
        'set_instance_assignment -name IO_STANDARD "2.5 V" -to clk',
        'set_location_assignment PIN_AC18 -to clk',
        'set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to "q[*]"',
        ('set_instance_assignment -name IO_STANDARD "'+$case[1]+'" -to "q[*]"'))
    $settings | Set-Content -LiteralPath (Join-Path $folder 'io_probe.qsf') -Encoding ascii
    Copy-Item -LiteralPath quartus/llm_soc.sdc -Destination (Join-Path $folder 'io_probe.sdc')
    Push-Location $folder
    try {
        foreach($stage in @('map','fit','sta')) {
            Write-Output ('PROBE_STAGE: '+$case[0]+' '+$stage)
            $args=if($stage -eq 'sta') {@('io_probe','-c','io_probe')} else {@('--read_settings_files=on','--write_settings_files=off','io_probe','-c','io_probe')}
            & (Join-Path $bin "quartus_$stage.exe") @args *> "$stage.log"
            if($LASTEXITCODE -ne 0) {Get-Content "$stage.log" -Tail 15;throw 'Probe stage failed'}
        }
        & (Join-Path $bin 'quartus_sta.exe') -t $extract $folder sdc (Join-Path $folder 'io_probe') *> 'extract.log'
        if($LASTEXITCODE -ne 0) {Get-Content 'extract.log' -Tail 15;throw 'Probe extract failed'}
        Write-Output ('PROBE_DONE: '+$case[0]+' '+$case[1]+'; I/O cell characterization only, not a full-top gate')
    } finally {Pop-Location}
}
