# ASIC portability and permitted implementation cells

[Documentation hub](../README.md) · [Full RTL graph](full_rtl_language.md) · [Arithmetic source](../source_guide/blocks/logic_mul.sv.md) · [Memory boundary](../source_guide/blocks/quartus_word_ram.sv.md)

The current compute and control RTL uses registers, muxes, comparisons, bitwise
logic, shifts, addition/subtraction, counters and FSMs. It instantiates no vendor
arithmetic, DSP, MAC, divider, square-root, FIFO, PLL, shift-register, floating-point
or Qsys/Platform Designer IP. Multipliers use `logic_mul`; there is no runtime
arithmetic multiplication or division operator in the datapath. Expressions in
generate geometry and constant bit-slice offsets are elaboration arithmetic,
not hardware multipliers or dividers. Runtime power-of-two address/word-count
calculations use explicit shifts; small constant address factors use shift/add.

The current candidate is `quartus_explicit2/llm_soc`, with 33 source assets
after removing the unused `ctrl_unit` and `hazard_detect`. Its QSF/QPF/SDC
matches the canonical full-top project. [Synthesis](../verification/synthesis/explicit2/manifest.json)
passed0errors/12warnings and [six units](../../tests/full_rtl/evidence/explicit3_six_units/results.json)
passed0compile/runtimewarnings; RTL/configuration are locked while graph and
fitting run. The [explicit RTL rules](rtl_style.md) now prohibit
synthesizable tasks, hidden sequential ownership and variable/unbounded loops.
All 61 request helpers are inline FSM updates; substantial replicated datapaths
and pipeline stages use generate blocks. LUTs are explicit combinational modules.

The [preceding seven-unit run](../../tests/full_rtl/evidence/logic6q5_all_units/results.json)
passed with official Quartus25.1 RAM on Questa2025.2, zero compile/runtime
warnings, for its archived35-source snapshot. Its synthetic graph generated
three RTL-selected tokens after two-token prefill and16layer executions.
These results cannot gate the changed source. Logic5/6 both fitted99.07MHz
but failed setup/hold/removal. Logic7 fitted96.04MHz and also failed;
its requested input delay chains were ignored by the actual Fitter.
No current100MHz timing PASS or trained application is claimed.

`logic_mul` has independently selected signedness for A and B. A is extended to
the output width, then each B bit masks a constant-shifted row. The signed top
bit contributes the negative shifted row through complement plus one. Each
compressor replaces three rows with XOR sum and shifted majority carry. One
ordinary adder combines the last two rows. The result is modulo `2^OUT_W`;
the caller owns rounding, saturation and overflow. Registers and valid/reset
pipelines remain in the callers, preserving the current operation latencies.
The divider uses shift/subtract with a borrow flag; integer square root uses
two-bit radicand steps and trial subtraction. No synthesis-specific compute
branches select a different algorithm.

The only explicit vendor primitive is `altsyncram`, confined to
`quartus_word_ram`. FPGA clients access it through `pipelined_word_ram` and the
bank/parameter adapters. ASIC integration replaces the memory technology leaf
with the selected foundry SRAM and matches its contract: common-clock 1R/1W,
one raw read edge, OLD_DATA for a simultaneous same-address read/write, and no
storage reset. If the macro has a different collision rule or latency, adapt it
inside this boundary and revalidate the existing collision/reset/cancellation
tests. Compute interfaces and numeric algorithms stay the same. ASIC physical
constraints, libraries, SRAM views and signoff checks remain technology work;
Quartus fitting is a synthesis/timing demonstration.

Memory-local `dont_merge` hints affect FPGA register placement only. ASIC tools
can ignore/remove these hints at the memory binding; compute/control has none.
QSF disables DSP and automatic shift-register recognition. QSF I/O standards,
pin locations and packed output-register requests are FPGA physical bindings,
not portable RTL or arithmetic IP.

The current candidate uses a single-ended 2.5-V 100-MHz clock on AC18,
reset on V28, and ordinary SDR LVDS output buffers. Every output has a physical
negative companion; an external host must receive this parallel differential
bus. There is no serializer, ALTLVDS or PLL. Board routing/termination has not
been supplied. The SDC remains 10 ns with the original input/output budgets,
no false paths and no multicycle paths. The output choice is based on a small
I/O characterization; full-top all-corner fitting must independently pass.

Current verification is recorded in [timing evidence](../verification/timing/README.md)
and [unit instructions](../../tests/full_rtl/README.md). Older PASS results apply
only to their archived source hashes. Application remains gated until the
current full-top fit/timing and all seven unit/graph groups pass.
