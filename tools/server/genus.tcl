# Common UI commands: https://community.cadence.com/cadence_technology_forums/f/digital-implementation/55520/genus-standard-cells-to-module
# This is synthesis of the portable inferred-memory backend, not SRAM binding/signoff.
if {[catch {
    set_db init_hdl_search_path [list $task_rtl]
    set_db library $task_libs
    read_hdl -sv $task_sources
    elaborate llm_soc -parameters {USE_QUARTUS_MEMORY 0}
    check_design -unresolved > [file join $task_report check_design.rpt]
    read_sdc $task_sdc
    syn_generic
    syn_map
    syn_opt
    report_area > [file join $task_report area.rpt]
    report_timing > [file join $task_report timing.rpt]
    write_hdl > [file join $task_report llm_soc.v]
    write_sdc > [file join $task_report llm_soc.sdc]
    puts "GENUS_FLOW_COMPLETED"
} task_error]} {
    puts stderr "GENUS_FLOW_FAILED: $task_error"
    exit 1
}
exit 0
