# Initial ASIC synthesis budgets, matching the existing 100 MHz host demo.
# Physical clocks, macro binding and signoff constraints require lab integration.
create_clock -name clk -period 10.000 [get_ports clk]
set_input_delay -clock clk -max 2.000 [remove_from_collection [all_inputs] [get_ports clk]]
set_input_delay -clock clk -min 0.500 [remove_from_collection [all_inputs] [get_ports clk]]
set_output_delay -clock clk -max 2.000 [all_outputs]
set_output_delay -clock clk -min -0.500 [all_outputs]
