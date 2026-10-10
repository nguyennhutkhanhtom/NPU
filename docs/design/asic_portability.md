# Ability to switch to ASIC and allowed implementation cells

<!-- reading-navigation:start -->
[Documentation](../README.md) → [05 · Implementation](../05-implementation/README.md) → This page

| Reading guide | Document |
|---|---|
| Read first | [Architecture map](../02-architecture/README.md) |
| Continue / related lookup | [SRAM binding contract](asic_memory_binding.md) |
<!-- reading-navigation:end -->

> **Category: POLICY.**

[SRAM binding guide for ASIC](asic_memory_binding.md) records the contract
leaf/client, all small arrays are inferred and evidenced by full-top elaboration
independent of vendor memory.

Current RTL compute and control uses registers, muxes, comparison operations, bitwise logic,
shifts, addition/subtraction, counters, and FSMs. RTL does not instantiate vendor arithmetic,
DSP, MAC, divider, square-root, FIFO, PLL, shift-register, floating-point or
Qsys/Platform Designer IP. Multiplier uses `logic_mul`; datapath does not have a
multiply or divide arithmetic operator at runtime. Expressions for generate geometry and constant
bit-slice offset are operations at elaboration, not multiplier or divider
hardware. Address/word-count calculations of power-of-two at runtime use direct shift;
small constant address factors use shift/add.

[RTL rules](rtl_style.md) prohibit synthesizable tasks, sequential ownership being obscured
and variable/unbounded loops. All 61 previous request helpers were inline
FSM update. Large replication parts and pipeline stage use generate block; LUT
is an explicit combinational module. The SIMD payload stage runs from captured operands,
with a nine-clock response contract. Two standard FFs assert internal reset immediately
and release after two rising edges. See [RTL policy](rtl_style.md).

`logic_mul` selects independent signedness for A and B. A is extended to output width,
then each bit of B masks a row shifted by a constant. The signed top bit contributes
the negative shifted row through two's complement. Each compressor replaces three rows with
XOR sum and shifted majority carry. A normal adder combines the last two rows.
Result according to modulo `2^OUT_W`; caller owns logic rounding, saturation, and overflow.
Register along with valid/reset pipeline still resides within caller, preserving operation latency
currently. Divider uses shift/subtract with borrow flag; integer square root processes
radicand two bits at a time and uses trial subtraction. There is no compute branch dedicated
specifically for synthesis to choose another algorithm.

The only direct vendor primitive is `altsyncram`, limited within
`quartus_word_ram`. Client accesses this primitive via `pipelined_word_ram` and
the banks/parameter adapters. When integrating ASIC, replace the memory technology leaf with
The chosen foundry SRAM follows and maintains the correct contract: common-clock 1R/1W, one raw read edge,
OLD_DATA when reading/writing simultaneously at the same address and without resetting storage. If
the macro has a different collision rule or latency, adjust it within this boundary
and re-verify the existing collision/reset/cancellation tests. Compute interface
and arithmetic algorithm remain unchanged. Physical constraint, library, SRAM view, and ASIC signoff checks
remain tasks according to technology; Quartus fitting only illustrates
synthesis/timing.

Local Hint `dont_merge` in memory only affects the placement register on
FPGA. ASIC tools can ignore or remove these hints during memory binding;
compute/control do not use them. QSF disables DSP and automatic shift-register
recognition. I/O standard, pin location, and packed output-register requests in
QSF are FPGA physical bindings, not RTL portable or arithmetic IP.

Quartus is an EDA demonstration backend. Assignments for device, pin, I/O standard,
fanout, and physical delay are in QSF; they do not become dependencies of
datapath/control ASIC. Demo SDC still maintains 10 ns with the initial input/output budget,
with no false path or multicycle path. This work does not include routing,
termination and peripheral bring-up on the FPGA board. Actual ASIC Synthesis/STA
using the chosen standard-cell library, SRAM view, and physical constraints.

Current verification and implementation status: [optimization status](../verification/optimization_status.md).
