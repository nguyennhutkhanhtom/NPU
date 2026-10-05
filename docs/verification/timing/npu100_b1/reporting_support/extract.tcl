# Post-fit timing reports for the existing routed Quartus netlist.
# Run: quartus_sta -t tools/timing/extract.tcl [output_dir] [1.0|sdc] [project] [path_count]
# Numeric clock periods deliberately reproduce a fixed internal-clock baseline.
# "sdc" reads the project's explicit timing constraints without changing them.
package require ::quartus::project
package require ::quartus::sta

set repo [file normalize [file join [file dirname [info script]] .. ..]]
set output [file join $repo docs verification timing user_baseline]
set constraint_mode 1.0
set project [file join $repo quartus matmul_free]
set path_count 40
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
if {[llength $quartus(args)] > 3} {
    set path_count [lindex $quartus(args) 3]
}
if {![string is integer -strict $path_count] || $path_count < 1 || $path_count > 1000} {
    error "Path count must be an integer from 1 through 1000"
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

# Audit physical register copies and direct timing-netlist fanout edges.
# This is report-only: it does not change assignments, constraints or placement.
set register_audit [open [file join $output implemented_registers.rpt] w]
puts $register_audit "Pattern\tRegister\tType\tFanout_edges\tLocation"
foreach pattern {*scalar_round_q* *scalar_packet* *scalar_cluster* *scalar_group_q* *token_prompt* token_q* *round16_group_q* *return_scalar*} {
    set matches [get_registers -nowarn $pattern]
    puts $register_audit "Count\t$pattern\t[get_collection_size $matches]"
    foreach_in_collection reg $matches {
        puts $register_audit "$pattern\t[get_node_info -name $reg]\t[get_node_info -type $reg]\t[llength [get_node_info -fanout_edges $reg]]\t[get_node_info -location $reg]"
    }
}
close $register_audit

# Cover all four voltage/temperature models used by this Cyclone V device.
# Explicit corner reports also retain each model's distinct critical endpoints.
foreach corner {{slow 85 1100} {slow 0 1100} {fast 85 1100} {fast 0 1100}} {
    lassign $corner model temperature voltage
    set corner_name ${model}_${voltage}mv_${temperature}c
    set_operating_conditions -model $model -temperature $temperature -voltage $voltage
    update_timing_netlist
    foreach analysis {setup hold recovery removal} {
        set command [list report_timing -$analysis -npaths $path_count -nworst 1 \
            -detail full_path -show_routing \
            -file [file join $output ${corner_name}_${analysis}.rpt]]
        eval $command
    }
    report_min_pulse_width -nworst $path_count -detail full_path \
        -file [file join $output ${corner_name}_pulse.rpt]
    report_clock_fmax_summary -file [file join $output ${corner_name}_fmax.rpt]

    # Retain a separate bounded sample for each changed family even when it
    # falls outside the global setup sample. Include the new pipeline stages.
    foreach {family from_patterns to_patterns} {
        scalar_distribution {*scalar_round_q* *scalar_packet* *scalar_cluster*} {*scalar_packet* *scalar_cluster* *scalar_group_q*}
        token_fetch {*graph* *token_prompt*} {*token_read_valid_q* *token_prompt* token_q*}
        round_control {op* *round16_group_q*} {*round16_group_q* *lane_round_q*}
        scalar_return {op*} {*return_scalar*}
    } {
        set family_from [get_registers -nowarn $from_patterns]
        set family_to [get_registers -nowarn $to_patterns]
        if {[get_collection_size $family_from] && [get_collection_size $family_to]} {
            report_timing -setup -from $family_from -to $family_to \
                -npaths 20 -nworst 1 -detail full_path -show_routing \
                -file [file join $output ${corner_name}_${family}.rpt]
        }
    }

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
        set critical_paths [get_timing_paths -setup -npaths $path_count -nworst 1]
        set statistics [::report_design_analysis::do_analysis_work \
            timing_tables timing_aggregate timing_path_table $path_count $critical_paths]
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
