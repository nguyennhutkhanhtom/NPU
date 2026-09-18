# Standalone ASIC IP synthesis, Genus Common UI. No FPGA flow or primitives.
# Required environment: TM_LIBS (Tcl list of Liberty paths), TM_SDC (SDC path).
# Optional: TM_PARAMETERS (named parameter/value pairs), TM_OUT (output path).
# Example TM_PARAMETERS: {{DATA_WIDTH 8} {DOT_LANES 16} {REDUCE_GROUP 4}}
# Run: genus -batch -abort_on_error -files tmatmul/synth/genus.tcl
set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir ../..]]
foreach name {TM_LIBS TM_SDC} {
    if {![info exists ::env($name)] || $::env($name) eq ""} {
        error "Set $name for the target standard-cell library and timing environment"
    }
}
foreach path $::env(TM_LIBS) {
    if {![file isfile $path]} {error "Missing Liberty file: $path"}
}
if {![file isfile $::env(TM_SDC)]} {error "Missing constraints: $::env(TM_SDC)"}
set out_dir [file join $script_dir out]
if {[info exists ::env(TM_OUT)]} {set out_dir [file normalize $::env(TM_OUT)]}
file mkdir $out_dir
set_db library $::env(TM_LIBS)
read_hdl -sv [list [file join $repo_dir {Verilog Source code} acc_mul.sv] \
                  [file join $repo_dir {Verilog Source code} ternary_mul.sv]]
if {[info exists ::env(TM_PARAMETERS)]} {
    elaborate ternary_mul -parameters $::env(TM_PARAMETERS)
} else {
    elaborate ternary_mul
}
check_design -unresolved
check_design -all > [file join $out_dir elaboration.rpt]
read_sdc $::env(TM_SDC)
check_timing_intent -verbose > [file join $out_dir constraints.rpt]
set_db syn_generic_effort high
set_db syn_map_effort high
set_db syn_opt_effort high
syn_generic
syn_map
syn_opt
check_design -all > [file join $out_dir design.rpt]
report_area > [file join $out_dir area.rpt]
report_gates > [file join $out_dir gates.rpt]
report_timing -max_paths 20 > [file join $out_dir timing.rpt]
report_messages > [file join $out_dir messages.rpt]
write_hdl > [file join $out_dir ternary_mul.v]
write_sdc > [file join $out_dir ternary_mul.sdc]
exit
