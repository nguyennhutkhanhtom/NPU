# Full RTL tests on the server

> **Category: GUIDE.**

Each testbench instantiates a named top, drives clocked transactions, and checks
specific assertions against an independent expectation. A testbench PASS covers
only the behaviors listed below and the exact compiled snapshot. For an
introduction to the verification levels, read
[From RTL to evidence](../../docs/00-start-here/fundamentals.md#from-rtl-to-evidence).

Run from the repo root on Linux Slurm using `tools/server/run_flow.py`.
[Running, configuration, and evidence guide](../../tools/server/README.md).
Do not use local PowerShell runners; they give errors pointing to the server flow.

| Testbench | Top | Scope |
|---|---|---|
| tb_memory_ip.sv | tb_llm_memory | Portable memory, expected independent words, OLD_DATA, latency, tiles, reset |
| tb_math.sv | tb_llm_math | Arithmetic, lookup, ternary, normalization |
| tb_ram.sv | tb_llm_ram | Adapter latency, lane masks, and reset cancellation |
| tb_protocol.sv | tb_llm_protocol | Host requests/writes/cancel/bounds |
| tb_selection.sv | tb_llm_selection | Excluded IDs, extrema and stable ties |
| tb_operators.sv | tb_llm_operators | Numeric operators and context/reset cases |
| tb_graph.sv | tb_llm_graph | Autonomous synthetic graph, causal/token/traffic assertions |
| tb_linear_stream.sv | tb_llm_linear_stream | Ordered rows, backpressure, faults and drain |
| host_cancel_contract.sv | tb_host_cancel_contract | Accepted portable SRAM commit before ACK and cancel |

Default `--stage test` runs all 9 groups. `--only TOP ...` is only selected PASS.
The runner transmits the absolute path of `sigmoid_257.mem` using `+SIGMOID_LUT=...`;
operator fixture rejects a missing LUT before arithmetic check. Private database of
each top does not depend on the checkout's root working directory.
Memory coverage of previous FPGA-IP equivalence is maintained in old evidence;
current flow does not verify FPGA IP and does not use the altera_mf library.

Application exporter runs on the compute node and writes new fixture through `--output`;
runner `--stage application --fixture PATH` checks reference/input/RTL hashes,
host-loads config/parameters/prompt and compares output tokens. Expected IDs not
control DUT. The result is functional token matching, no hardware/signoff gate.

The scripts memory_model.py/check_gate.py/finalize_application.py still retain helpers
to read the old evidence structure; local entry points have been blocked. Old evidence does not
replace regression/synthesis of the new portable configuration.
