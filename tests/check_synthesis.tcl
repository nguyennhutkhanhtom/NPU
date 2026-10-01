# Optional Quartus smoke checks for the portable descriptor and memory RTL.
load_package flow
set repo [file normalize [file join [file dirname [info script]] ..]]
set rtl [file join $repo {Verilog Source code}]
foreach top {descriptor_file sram_256_wrapper ins_mem} {
    set build [file join $repo tests sim synth_$top]
    file mkdir $build
    project_new [file join $build $top] -overwrite
    set_global_assignment -name FAMILY {Cyclone V}
    set_global_assignment -name DEVICE 5CGXFC7C7F23C8
    set_global_assignment -name TOP_LEVEL_ENTITY $top
    set_global_assignment -name SYSTEMVERILOG_FILE [file join $rtl npu_pkg.sv]
    set_global_assignment -name SYSTEMVERILOG_FILE [file join $rtl $top.sv]
    set_global_assignment -name PROJECT_OUTPUT_DIRECTORY output_files
    set_global_assignment -name SYNTHESIS_EFFORT FAST
    set_global_assignment -name OPTIMIZATION_TECHNIQUE AREA
    set_global_assignment -name PARALLEL_SYNTHESIS OFF
    set_global_assignment -name NUM_PARALLEL_PROCESSORS 1
    execute_module -tool map
    project_close
    set file [open [file join $build output_files $top.map.rpt] r]
    set report [read $file]
    close $file
    if {[regexp {Inferred latch} $report]} {
        error "$top inferred an unintended latch"
    }
    if {$top eq "sram_256_wrapper" &&
        ![regexp {Total block memory bits\s*;\s*65536\s*;} $report]} {
        error "SRAM did not map all 65536 bits to block RAM"
    }
    if {$top eq "ins_mem"} {
        if {![regexp {Total block memory bits\s*;\s*6656\s*;} $report]} {
            error "Instruction memory did not map all 6656 bits to block RAM"
        }
        if {![regexp {Dedicated logic registers\s*;\s*([0-9]+)\s*;} $report -> registers] || $registers > 128} {
            error "Instruction memory expanded into registers"
        }
    }
    puts "SYNTHESIS_STRUCTURE_PASS: $top"
}
