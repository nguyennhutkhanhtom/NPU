# SRAM Connection When Transitioning to ASIC

<!-- reading-navigation:start -->
[Documentation](../README.md) → [05 · Implementation](../05-implementation/README.md) → This page

| Reading guide | Document |
|---|---|
| Read first | [ASIC portability](asic_portability.md) |
| Continue / related lookup | [Portable SRAM implementation](../source_guide/blocks/sram_word_tile.sv.md) |
<!-- reading-navigation:end -->

> **Category: GUIDE.**

The compute/control block still uses synthesizable SystemVerilog. Current technology leaf
is `quartus_word_ram`, accessed via `pipelined_word_ram`; only this source
instantiates `altsyncram` directly. When implementing ASIC, a
technology-specific replacement must be provided while keeping the same public leaf interface, then select that source
in the ASIC file list. Keep the adapter branch and existing client interfaces unchanged.
The name `USE_QUARTUS_MEMORY` currently selects this leaf branch; it does not require arithmetic logic
or Quartus control.

The Core only has one `clk`. The host request/data signals must meet the contract
setup/hold of this clock and remain stable throughout the handshake. RTL does not provide
a separate host clock or CDC data bridge. When integrating ASIC with a host in a different clock
domain, that bridge must be added upstream; two reset-release FFs only synchronize
the timing of deasserting reset, not host data.

The portable branch (`USE_QUARTUS_MEMORY=0`) uses `sram_word_tile` arrays that are inferred.
Vendor-free elaboration only checks independence from the vendor model; this result
does not prove ASIC implementation/signoff. See [verification status](../verification/optimization_status.md).

## Leaf contract and client

Leaf has a shared rising-edge clock, one read port, and one write port, with
separate addresses and whole-word write enable. When read is enabled, the address is sampled
at the rising edge and the corresponding word appears after that edge. When read is disabled,
the most recent result is held. Write enabled will commit at that edge. If
read/write occur simultaneously at the same address, read returns the old word. Leaf has no reset
port; content/output at power-up is undefined. Client and test are not allowed to
read uninitialized memory. Adapter control reset cancels pending enables and
valid response, but keeps committed data; payload register is not reset.

| Full-top client | Leaf instances and geometry | Adapter contract |
|---|---|---|
| Parameter SRAM | 8 × 32 bits × 24576 rows | Compute read 5 edges; host read lane selection adds 1 edge before controller response. Write ACK according to actual leaf commit. |
| KV cache | 32 × 24 bits × 4096 rows | Read 5 edges; lane-masked write commit at edge 4; busy covers pending write. |
| Vector workspace | 32 × 24 bits × 96 rows | Read 5 edges; lane-masked write commit at edge 4; use the same reset/collision contract. |

Latency for the edge receiving is edge 1. Word adapter uses read 3 edges when there are
<=4096 rows and 4 edges in the remaining case; write commit at edge 2. The
stage request group/lane creates the latency of the above bank adapter. Throughput
and collision behavior are checked by independent expected data along with the actual Quartus model
in [current verification status](../verification/optimization_status.md).
When changing macro port, read latency, or collision semantics, adjustments must be made
this boundary and rerun the corresponding tests. Collision response is undefined
cannot be considered equivalent to OLD_DATA. Macro selection must take into account the rules
and the accepted request rate of the adapter.

## Small arrays owned by the graph controller

`llm_soc` also contains four 128-entry arrays with clearly visible read/write operations in
the host/graph/operator FSMs. These are regular inferred RTL arrays, not
directly instantiated from vendors. They can maintain register/mux forms in the implementation
of the ASIC standard-cell. If switched to SRAM, the read sampling method and the
Current FSM stage; adding an unconsidered read edge will change the behavior of the graph.

| Array | Logical payload | Source ownership and initialization |
|---|---:|---|
| prompt_memory | 128 × 12 bits = 192 bytes | Host writes prompt ID before launch; graph reads these IDs during prefill. |
| output_memory | 128 × 12 bits = 192 bytes | Graph writes the selected token; host reads these returned IDs. |
| score_memory | 128 × S32 = 512 bytes | Operator writes causal score from 0..position before exponentiation reads them. |
| probability_memory | 128 × U25 = 400 bytes | Operator writes exponent weight from 0..position before value reduction reads them. |

These arrays are not reset; ownership of count/state determines which entry is valid.
[Fanout1 fitter report](../verification/timing/fullrtl100_fanout1/llm_soc.fit.rpt)
map 1536 bits of output_memory and 3200 bits of probability_memory into two RAMs
additional block. 72 leaf instances directly occupy 9,510,912 logical bits; plus
4,736 inferred bits resulting in 9,515,648 block-memory bits as reported. The prompt/score arrays
use logic resources in this fit. ASIC mapping does not need to copy that packing method.
Forwarding logic report276020 of output RAM is inferred to preserve read-during-write
semantics in the source; this is not a separate datapath IP instance.

## EDA input when there is a foundry target

Use the same source compute/control, package, and combinational LUT include of
`llm_soc` in the [source guide](../source_guide/blocks/README.md). Replace the source of
memory technology leaf and provide the behavioral/Liberty/LEF views of the selected SRAM
along with the standard-cell library. Keep the contract numeric/reset/handshake unchanged and
rerun unit, collision, cancellation, and autonomous graph tests with that leaf.
Use synthesis/STA ASIC constraints for real clock, I/O environment, and library
corner; complete DFT and physical signoff using the corresponding technologies. The
assignment of device, pin, fanout, and delay in Quartus QSF only belongs to demonstration
backend. This work does not include board integration.
