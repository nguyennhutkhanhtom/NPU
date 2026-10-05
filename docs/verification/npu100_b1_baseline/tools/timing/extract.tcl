# Post-fit timing reports for the existing routed Quartus netlist.
# Run: quartus_sta -t tools/timing/extract.tcl [output_dir] [1.0|sdc] [project]
# Numeric clock periods deliberately reproduce a fixed internal-clock baseline.
# "sdc" reads the project's explicit timing constraints without changing them.
package require ::quartus::project
package require ::quartus::sta

set repo [file normalize [file join [file dirname [info script]] .. ..]]
set output [file join $repo docs verification timing user_baseline]
set constraint_mode 1.0
set project [file join $repo quartus matmul_free]
if {[llength $quartus(args)] > 0} {
    set output [file normalize [lindex $quartus(args) 0]]
}
if {[llength $quartus(args)] > 1} {
    set constraint_mode [lindex $quartus(args) 1]
}
if {[llength $quartus(args)] > 2} {
    set project [file normalize [lindex $quartus(args) 2]]
    if {[file extension $project] in {.qpf .qsf}} {
        set project [file rootname $project]
    }
}
if {$constraint_mode ne "sdc" &&
    (![string is double -strict $constraint_mode] || $constraint_mode <= 0)} {
    error "Clock argument must be a positive period in ns or sdc"
}
file mkdir $output
cd [file dirname $project]
project_open [file tail $project] -revision [file tail $project]
create_timing_netlist
if {$constraint_mode eq "sdc"} {
    read_sdc
} else {
    create_clock -name clk -period $constraint_mode [get_ports clk]
    derive_clock_uncertainty
}
update_timing_netlist

report_sdc -file [file join $output extracted_sdc.rpt]
report_ucp -summary -file [file join $output extracted_unconstrained.rpt]
check_timing -file [file join $output extracted_checks.rpt]

# Cover all four voltage/temperature models used by this Cyclone V device.
# Explicit corner reports also retain each model's distinct critical endpoints.
foreach corner {{slow 85 1100} {slow 0 1100} {fast 85 1100} {fast 0 1100}} {
    lassign $corner model temperature voltage
    set corner_name ${model}_${voltage}mv_${temperature}c
    set_operating_conditions -model $model -temperature $temperature -voltage $voltage
    update_timing_netlist
    foreach analysis {setup hold recovery removal} {
        set command [list report_timing -$analysis -npaths 40 -nworst 1 \
            -detail full_path -show_routing \
            -file [file join $output ${corner_name}_${analysis}.rpt]]
        eval $command
    }
    report_min_pulse_width -nworst 40 -detail full_path \
        -file [file join $output ${corner_name}_pulse.rpt]
    report_clock_fmax_summary -file [file join $output ${corner_name}_fmax.rpt]

    # Quartus 18.1 implements closure recommendations in its bundled Tcl.
    # Export the heuristic tables directly because plain-text STA exports omit
    # HTML panels. This does not change the original .sta.rpt report database.
    set recommendations [open [file join $output ${corner_name}_recommendations.txt] w]
    if {[catch {
        if {![llength [info commands ::report_design_analysis::do_analysis_work]]} {
            source [file join $quartus(binpath) .. common tcl internal qsta_report_design_analysis.tcl]
        }
        if {![has_design_analysis_support]} {
            error "Timing closure recommendation heuristics unavailable for this database"
        }
        array set timing_tables {}
        array set timing_aggregate {}
        set timing_path_table {}
        set critical_paths [get_timing_paths -setup -npaths 40 -nworst 1]
        set statistics [::report_design_analysis::do_analysis_work \
            timing_tables timing_aggregate timing_path_table 40 $critical_paths]
        puts $recommendations "Statistics: $statistics"
        foreach heuristic [lsort [array names timing_tables]] {
            puts $recommendations "\nHeuristic: $heuristic"
            foreach row $timing_tables($heuristic) {
                puts $recommendations $row
            }
            if {$heuristic ne "Summary" && [llength $timing_tables($heuristic)] > 1} {
                set html [open [file join $output ${corner_name}_recommendations_${heuristic}.html] w]
                puts $html [::report_design_analysis::html_page_report \
                    $heuristic $timing_tables($heuristic) \
                    "Timing closure recommendations: $corner_name" $timing_aggregate($heuristic)]
                close $html
            }
        }
    } recommendation_error]} {
        puts $recommendations "Unavailable: $recommendation_error"
        post_message -type info "Recommendation export unavailable: $recommendation_error"
    }
    close $recommendations
    unset -nocomplain timing_tables timing_aggregate
    puts "TIMING_CORNER_EXTRACTED: $corner_name"
}
delete_timing_netlist
project_close -dont_export_assignments
puts "TIMING_EXTRACTION_PASS: $output ($constraint_mode)"
