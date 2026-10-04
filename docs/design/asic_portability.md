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

The current full-top candidate uses the isolated `quartus_logic5/llm_soc`
database; its QSF/QPF/SDC bytes match `quartus/llm_soc` exactly, and both point
to the same35source assets. Analysis & Synthesis has passed0errors/12warnings
on Quartus Lite25.1std.0 Build1129; Fitter/STA are pending. Legacy regression
has passed10groups for these source hashes with0runtimewarnings. Six full-top
unit groups passed, including17operators/3460checks/scalar128/clamp128, with
0runtimewarnings. Actual-IP graph remains required after hardware timing passes.
See [synthesis-only archive](../verification/synthesis/logic4/manifest.json),
[six-unit archive](../../tests/full_rtl/evidence/logic4_six_units/results.json) and
[legacy regression archive](../../tests/evidence/logic4_units/results.json).

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

The current `fullrtl100_logic5` candidate uses a single-ended 2.5-V 100-MHz clock on AC18,
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
