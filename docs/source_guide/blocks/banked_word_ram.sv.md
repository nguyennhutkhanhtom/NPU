# banked_word_ram.sv

<!-- reading-navigation:start -->
[Documentation](../../README.md) → [Archive · Legacy](../../archive/README.md) → [Module catalog](README.md)

| Reading guide | Document |
|---|---|
| Read first | [Legacy architecture](../../design/legacy/architecture.md) |
| Related implementation | [sram_word_tile.sv](sram_word_tile.sv.md) |
<!-- reading-navigation:end -->

> **Category: GUIDE. Scope: LEGACY.** RTL is authoritative; diagrams use the [shared visual style](../../diagrams/diagram_style.md).

**Source:** [banked_word_ram.sv](<../../../Verilog%20Source%20code/banked_word_ram.sv>).

## At a glance

| Item | Description |
|---|---|
| Responsibility | Legacy three-pass RMS normalization and quantization. Two shared structural multipliers, one divider and the separately defined isqrt_u64 serve the explicit pass controller. Workspace scratch and final quantized values are packed in 256-bit words. |

## Architecture diagram

![banked_word_ram.sv — overview](../../diagrams/previews/16_banked_word_ram.sv_1.svg)

[Editable draw.io — banked_word_ram.sv — overview](../../diagrams/architecture.drawio) · Page `16_banked_word_ram.sv_1`.
