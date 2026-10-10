# llm_pkg.sv — Layout, saturation and sampler

<!-- reading-navigation:start -->
[Documentation](../../README.md) → [02 · Architecture](../../02-architecture/README.md) → [Module catalog](README.md)

| Reading guide | Document |
|---|---|
| New to the subject | [NPU and RTL fundamentals](../../00-start-here/fundamentals.md) · [Glossary](../../00-start-here/glossary.md) |
| Read first | [Full RTL graph](../full_graph.md) |
| Related implementation | [llm_soc.sv](llm_soc.sv.md) |
<!-- reading-navigation:end -->

**Package constants.** The fixed graph constants use typed package `parameter` declarations according to the lowRISC package convention. Values, signed `int` types and all references are preserved; module geometry remains unchanged.

> **Category: GUIDE. Scope: CURRENT (may also have legacy callers).** RTL is authoritative; diagrams use the [shared visual style](../../diagrams/diagram_style.md).

**Source:** [llm_pkg.sv](<../../../Verilog%20Source%20code/llm_pkg.sv>).

## At a glance

| Item | Description |
|---|---|
| Responsibility | Fixed graph constants for NanoFable, parameter rows addresses, S24 saturation, sign extension, and xorshift32. LUT exp/Gumbel is included as portable logic. |

## Architecture diagram

![llm_pkg.sv — overview](../../diagrams/previews/30_llm_pkg.sv_1.svg)

[Editable draw.io — llm_pkg.sv — overview](../../diagrams/architecture.drawio) · Page `30_llm_pkg.sv_1`.

## Important state / datapath groups

### [Lines 1–10: Layout constants](<../../../Verilog%20Source%20code/llm_pkg.sv#L1>)

PARAM_ROWS=24576; address calculated by 256-bit row. EMB_SCALE, matrix metadata, gains, and RoPE are located after weights.

### [Lines 11–20: Numeric helpers](<../../../Verilog%20Source%20code/llm_pkg.sv#L11>)

Saturation at ±2^23; llm_extend56 preserves the sign of the SIMD product before RNE64.

### [Lines 21–31: Sampler](<../../../Verilog%20Source%20code/llm_pkg.sv#L21>)

Deterministic Xorshift32, zero seed replaced by controller with one. Zero temperature for greedy argmax.
