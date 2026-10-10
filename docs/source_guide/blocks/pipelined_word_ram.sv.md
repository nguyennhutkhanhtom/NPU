# pipelined_word_ram.sv

**Structural generation.** Named SystemVerilog generate constructs are retained without the optional `generate`/`endgenerate` regions, following lowRISC. Loop bounds, conditional branches, instance names and lane ownership are unchanged.

> **Category: GUIDE. Scope: CURRENT (may also have legacy callers).** RTL is authoritative; diagrams use the [shared visual style](../../diagrams/diagram_style.md).
[Documentation](../../README.md) → [Source guide](../full_graph.md) → [RTL index](README.md)

**Source:** [pipelined_word_ram.sv](<../../../Verilog%20Source%20code/pipelined_word_ram.sv>).

## At a glance

| Item | Description |
|---|---|
| Responsibility | Replaceable SRAM adapter. USE_QUARTUS_MEMORY=1 selects 1024-word Quartus tiles when ROWS exceeds 4096, otherwise one whole-bank Quartus leaf. The portable branch uses 1024-word sram_word_tile leaves. Grouped responses preserve three-edge reads for up to four tiles and four-edge reads for larger banks. Writes commit one edge after capture; reset cancels queued enables and validity while preserving storage. |

## Architecture diagram

![pipelined_word_ram.sv — overview](../../diagrams/previews/50_pipelined_word_ram.sv_1.svg)

[Editable draw.io — pipelined_word_ram.sv — overview](../../diagrams/architecture.drawio) · Page `50_pipelined_word_ram.sv_1`.
