# ASIC portability and permitted implementation cells

> **Category: POLICY.**

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

The [explicit RTL rules](rtl_style.md) prohibit synthesizable tasks, hidden sequential ownership and variable/unbounded loops. All61former request helpers are inline FSM updates. Significant replication and pipeline stages use generate blocks; LUTs are explicit combinational modules. SIMD payload stages run from captured operands, with a nine-clock response contract. Two standard FFs assert internal reset immediately and release it after two rising edges. See [RTL policy](rtl_style.md).

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

Current verification and implementation status: [optimization status](../verification/optimization_status.md).
