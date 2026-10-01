# Timing demo for the portable core, not a board or ASIC sign-off constraint.
# Keep these budgets identical when comparing RTL revisions.
create_clock -name clk -period 20.000 [get_ports clk]
derive_clock_uncertainty

# Synchronous host and reset-release assumptions: external data arrives
# 0.5..2.0 ns after clk; the external receiver needs 2.0 ns setup/0.5 ns hold.
# No functional path is hidden by a false-path or multicycle exception.
set_input_delay -clock clk -max 2.000 [remove_from_collection [all_inputs] [get_ports clk]]
set_input_delay -clock clk -min 0.500 [remove_from_collection [all_inputs] [get_ports clk]]
set_output_delay -clock clk -max 2.000 [all_outputs]
set_output_delay -clock clk -min -0.500 [all_outputs]
