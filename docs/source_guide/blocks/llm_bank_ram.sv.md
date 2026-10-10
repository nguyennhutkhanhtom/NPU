# llm_bank_ram.sv — Lane-masked SRAM for graph

**Structural generation.** Named SystemVerilog generate constructs are retained without the optional `generate`/`endgenerate` regions, following lowRISC. Loop bounds, conditional branches, instance names, and lane ownership are unchanged.

> **Category: GUIDE. Scope: CURRENT (may also have legacy callers).** RTL is authoritative; diagrams use the [shared visual style](../../diagrams/diagram_style.md).
[Document](../../README.md) → [Source guide](../README.md) → [Table of contents](README.md)

**Source:** [llm_bank_ram.sv](<../../../Verilog%20Source%20code/llm_bank_ram.sv>).

## At a glance

| Item | Description |
|---|---|
| Responsibility | 32-lane S24 creates 768-bit rows. USE_QUARTUS_MEMORY selects FPGA IP or ASIC model via word adapter. Requests go through a group of four lanes, lane register, and adapter register before storage; read valid on five edges with ROWS≤4096, write commit on the fourth edge. wr_busy forces the operator to drain before completion. Reset clears queue/valid, keeps storage/payload. |

## Architecture diagram

![llm_bank_ram.sv — overview](../../diagrams/previews/24_llm_bank_ram.sv_1.svg)

[Editable draw.io — llm_bank_ram.sv — overview](../../diagrams/architecture.drawio) · Page `24_llm_bank_ram.sv_1`.

## Important state / datapath groups

### [Lines 1–24: Interface and write pending](<../../../Verilog%20Source%20code/llm_bank_ram.sv#L1>)

The client uses rd_valid; the operator must wait for wr_busy to lower before reporting done. Latency includes group, lane, and tile stages.

### [Lines 25–47: Group request distribution](<../../../Verilog%20Source%20code/llm_bank_ram.sv#L25>)

Address/data payload is latched without enabling the mux. SRAM-only dont_merge maintains locality; read/write enables reset to cancel queued requests.

### [Lines 48–76: Lane banks and response](<../../../Verilog%20Source%20code/llm_bank_ram.sv#L48>)

Leaf old-data collision tracks the same accepted cycle. Lane-valid has the same latency; output uses lane0 valid to confirm the entire row.
