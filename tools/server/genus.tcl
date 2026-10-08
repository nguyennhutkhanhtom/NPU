# Common UI commands: https://community.cadence.com/cadence_technology_forums/f/digital-implementation/55520/genus-standard-cells-to-module
# Optional storage black boxes are exploration placeholders, not SRAM binding/signoff.
if {[catch {
    set task_progress [open [file join $task_report synthesis_progress.log] w]
    puts $task_progress "START library/read_hdl"; flush $task_progress
    set_db init_hdl_search_path [list $task_rtl]
    set_db library $task_libs
    # Match the two-CPU Slurm allocation; the installed tool otherwise defaults to eight.
    set_db max_cpus_per_server 2
    if {$task_ram_blackbox} {
        set_db init_blackbox_for_undefined true
        set_db hdl_error_on_blackbox false
        read_hdl -sv -define SYNTH_RAM_BLACKBOX $task_sources
    } else {
        read_hdl -sv $task_sources
    }
    puts $task_progress "START elaborate $task_top"; flush $task_progress
    # llm_soc defaults USE_QUARTUS_MEMORY to 0 in the frozen source.
    # A flat named/value list is interpreted as positional expressions by Genus 21.1.
    elaborate $task_top
    check_design -unresolved > [file join $task_report check_design.rpt]
    read_sdc $task_sdc
    puts $task_progress "START syn_generic"; flush $task_progress
    syn_generic
    report_area > [file join $task_report generic_area.rpt]
    puts $task_progress "START syn_map"; flush $task_progress
    syn_map
    puts $task_progress "START syn_opt"; flush $task_progress
    syn_opt
    check_design -unresolved > [file join $task_report check_design_mapped.rpt]
    report_area > [file join $task_report area.rpt]
    report_timing > [file join $task_report timing.rpt]
    write_hdl > [file join $task_report ${task_top}.v]
    write_sdc > [file join $task_report ${task_top}.sdc]
    puts $task_progress "GENUS_FLOW_COMPLETED"
    close $task_progress
    puts "GENUS_FLOW_COMPLETED"
} task_error]} {
    puts stderr "GENUS_FLOW_FAILED: $task_error"
    exit 1
}
exit 0
