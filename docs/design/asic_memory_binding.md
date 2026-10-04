# SRAM binding for ASIC migration

[Documentation hub](../README.md) · [Portable RTL policy](asic_portability.md) · [Full graph](full_rtl_language.md) · [Memory tests](../../tests/full_rtl/tb_memory_ip.sv)

Compute/control remain synthesizable SystemVerilog. The current technology
leaf is `quartus_word_ram`, reached through `pipelined_word_ram`; only that
source explicitly instantiates `altsyncram`. For an ASIC implementation,
provide a technology-specific replacement with the same public leaf interface
and select its source in the ASIC file list. Keep the existing adapter branch
and client interfaces. The `USE_QUARTUS_MEMORY` name currently selects this
leaf branch; it does not require Quartus arithmetic or control logic.

The core has one `clk`. Its host request/data signals must meet that clock's
setup/hold contract and stay stable through the handshake. The RTL provides
no independent host clock or data CDC bridge. ASIC integration with a host in
another clock domain must provide that bridge upstream; the two reset-release
FFs synchronize reset deassertion, not host data.

The portable branch (`USE_QUARTUS_MEMORY=0`) uses inferred `sram_word_tile`
arrays. [Preceding full-top elaboration evidence](../verification/portable_elaboration1/results.json)
passes with no vendor memory library loaded,24 module design units,14 unique
module names and0errors/0warnings. The binding report contains no `altsyncram`
or vendor datapath. This was `run 0`, with no weights or inference; it proves
elaboration independence from the vendor memory model. It does not select a
foundry macro or establish ASIC synthesis, timing or physical signoff.

## Leaf contract and clients

The leaf has one common rising-edge clock, one read port and one write port,
separate addresses and whole-word write enables. An enabled read samples its
address on the rising edge and exposes that word after the edge. A disabled
read holds the last result. An enabled write commits on that edge. A simultaneous
same-address read/write returns the old word to the reader. There is no reset
port; power-up contents/output are unspecified. Neither client nor test may
consume uninitialized memory. Adapter control reset cancels queued enables and
valid responses while retaining committed data; payload registers are unreset.

| Full-top client | Leaf instances and geometry | Adapter contract |
|---|---|---|
| Parameter SRAM |8 ×32 bits ×24576 rows | Compute read5edges; host read lane selection adds1edge before controller response. Write ACK follows actual leaf commit. |
| KV cache |32 ×24 bits ×4096 rows | Read5edges; lane-masked write commits at edge4; busy covers pending writes. |
| Vector workspace |32 ×24 bits ×96 rows | Read5edges; lane-masked write commits at edge4; same reset/collision contract. |

Latencies count the accepting edge as edge1. The word adapter uses read3edges
for<=4096rows and4otherwise; write commit at edge2. Group/lane request stages
account for the bank adapter latencies above. Throughput and collision behavior
are checked against independent expected data and the actual Quartus model in
the [current seven-group archive](../../tests/full_rtl/evidence/pipeline3_all_units/results.json).
Changing macro ports, read latency or collision semantics requires adapting
this boundary and rerunning those checks. An undefined collision response cannot
be declared equivalent to OLD_DATA. Macro selection must account for that rule
and for the adapter's accepted request rate.

## Smaller arrays owned by the graph controller

`llm_soc` also contains four128-entry arrays, with visible reads/writes in its
host/graph/operator FSMs. These are ordinary inferred RTL arrays, with no
explicit vendor instantiation. They can remain registers/muxes in an ASIC
standard-cell implementation. Mapping them to SRAM instead requires preserving
the existing read sampling and FSM stages; adding an unaccounted read edge
would change graph behavior.

| Array | Logical payload | Source ownership and initialization |
|---|---:|---|
| prompt_memory |128 ×12bits =192bytes | Host fills prompt IDs before launch; graph consumes them during prefill. |
| output_memory |128 ×12bits =192bytes | Graph writes selected tokens; host reads returned IDs. |
| score_memory |128 ×S32 =512bytes | Operator writes causal scores0..position before exponentiation reads them. |
| probability_memory |128 ×U25 =400bytes | Operator writes exponent weights0..position before value reduction reads them. |

These arrays are unreset; count/state ownership determines valid entries.
The [fanout1 fitter report](../verification/timing/fullrtl100_fanout1/llm_soc.fit.rpt)
maps output_memory1536bits and probability_memory3200bits to two extra RAM
blocks. The72 explicit leaf instances account for9510912logical bits; adding
those4736inferred bits gives the reported9515648block-memory bits. Prompt/score
arrays use logic resources in this fit. ASIC mapping need not copy this packing.
The inferred output RAM's report276020 forwarding logic preserves its source
read-during-write semantics; it is not a separate datapath IP instantiation.

## EDA inputs when a foundry target is available

Use the same `llm_soc` compute/control sources, packages and combinational LUT
includes from the [source guide](../source_guide/blocks/README.md). Replace the
memory technology leaf source and supply the chosen SRAM behavioral/Liberty/LEF
views together with standard-cell libraries. Keep numeric/reset/handshake
contracts and rerun unit, collision, cancellation and autonomous graph tests
against that leaf. Use ASIC synthesis/STA constraints for the actual clock,
I/O environment and library corners; complete DFT and physical signoff with
those technologies. Quartus QSF device, pin, fanout and delay assignments belong
only to the demonstration backend. No board integration is part of this work.
