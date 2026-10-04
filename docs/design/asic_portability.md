# ASIC portability and permitted implementation cells

[Documentation hub](../README.md) · [Full RTL graph](full_rtl_language.md) · [Arithmetic source](../source_guide/blocks/logic_mul.sv.md) · [Memory boundary](../source_guide/blocks/quartus_word_ram.sv.md)

[ASIC SRAM binding guide](asic_memory_binding.md) records leaf/client contracts,
all smaller inferred arrays and vendor-memory-free full-top elaboration evidence.

The current compute and control RTL uses registers, muxes, comparisons, bitwise
logic, shifts, addition/subtraction, counters and FSMs. It instantiates no vendor
arithmetic, DSP, MAC, divider, square-root, FIFO, PLL, shift-register, floating-point
or Qsys/Platform Designer IP. Multipliers use `logic_mul`; there is no runtime
arithmetic multiplication or division operator in the datapath. Expressions in
generate geometry and constant bit-slice offsets are elaboration arithmetic,
not hardware multipliers or dividers. Runtime power-of-two address/word-count
calculations use explicit shifts; small constant address factors use shift/add.

The [explicit RTL rules](rtl_style.md) prohibit synthesizable tasks, hidden sequential ownership and variable/unbounded loops. All61former request helpers are inline FSM updates. Significant replication and pipeline stages use generate blocks; LUTs are explicit combinational modules. SIMD payload stages run from captured operands, with a nine-clock response contract. Two standard FFs assert internal reset immediately and release it after two rising edges. The [current policy review](../verification/rtl_policy_cache1/results.json) records the exact34-source snapshot and reviewed loop/function/arithmetic inventory.

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
`quartus_word_ram`. Clients access it through `pipelined_word_ram` and the
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

Quartus is the EDA demonstration backend. Device, pin, I/O standard, fanout and physical-delay assignments stay in its QSF; they do not become ASIC datapath/control dependencies. The demo SDC remains10ns with the original input/output budgets, no false paths or multicycle paths. FPGA board routing, termination and peripheral bring-up are outside this work. Actual ASIC synthesis/STA uses the selected standard-cell libraries, SRAM views and physical constraints.

Current verification is recorded in [timing evidence](../verification/timing/README.md)
and [unit instructions](../../tests/full_rtl/README.md). Older PASS results apply
only to their archived source hashes. Application remains gated until the
current full-top fit/timing and all seven unit/graph groups pass.

The preceding `attention1` source clears attention accumulators at each head entry, removing the conditional late-clear cone measured in the preceding fit. [Synthesis](../verification/synthesis/attention1/manifest.json) PASS0errors/12warnings; [attention1 all seven groups](../../tests/full_rtl/evidence/attention1_all_units/results.json) PASS0warnings, including full graph4229462compute clocks. [Attention1 vendor-free elaboration](../verification/portable_elaboration_attention1/results.json) also PASS0errors/0warnings. Attention1 all-corner timing FAIL92.19MHz/setup+recovery; hold PASS every corner. The preceding [fanout2 fit](../verification/timing/fullrtl100_fanout2/manifest.json) fails96.67MHz/setup+hold. Historical results and critical paths remain in the timing hub. No current100MHz or trained application PASS is claimed.

Current cache1 separates generated continuous KV payload FFs from the held binary operand. Consumers still follow cache valid; no FSM state/clock/latency/expected-value change. [Seven groups](../../tests/full_rtl/evidence/cache1_all_units/results.json) PASS0compile/runtimewarnings, graph4229462compute clocks/three RTL-selected tokens/16layer executions/causal checked; full timing FAIL73.97MHz/setup+recovery; hold/removal/pulse PASS every corner/UCP0. Host reset still clears response immediately; QSF global-routing request is backend-only, not compute/control IP or ASIC signoff. [Current vendor-free elaboration](../verification/portable_elaboration_cache1/results.json) PASS24module units/14names/0errors0warnings, run0/no weights/inference. Preceding timing evidence applies to its archived attention1 source; no current100MHz or trained application PASS.

Backend cache2 removes the forced-global QSF routing request after cache1 recommendations identified its failing path. No RTL, test input, SRAM contract or SDC change; exact cache1 seven-group/vendor-free PASS remains applicable to the same source. Fresh full synthesis/fit/all-corner timing is running; no application gate is open.
