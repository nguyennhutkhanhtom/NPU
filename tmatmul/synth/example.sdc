# Example only: replace these values with the integration timing budget.
# Verify the tool's time and capacitance units for the selected library.
# No datapath multicycle or false-path exceptions are needed by this RTL.
create_clock -name core_clk -period 2.0 [get_ports clk]
set_clock_uncertainty 0.1 [get_clocks core_clk]
set data_inputs [remove_from_collection [all_inputs] [get_ports clk]]
set_input_delay -max 0.2 -clock core_clk $data_inputs
set_input_delay -min 0.0 -clock core_clk $data_inputs
set_input_transition 0.1 $data_inputs
set_output_delay -max 0.2 -clock core_clk [all_outputs]
set_output_delay -min 0.0 -clock core_clk [all_outputs]
set_load 0.01 [all_outputs]
