# llm_attention_engine.sv

<!-- reading-navigation:start -->
[Documentation](../../README.md) → [02 · Architecture](../../02-architecture/README.md) → [Module catalog](README.md)

| Reading guide | Document |
|---|---|
| New to the subject | [NPU and RTL fundamentals](../../00-start-here/fundamentals.md) · [Glossary](../../00-start-here/glossary.md) |
| Read first | [Full RTL graph](../full_graph.md) |
| Related implementation | [llm_attention_normalize.sv](llm_attention_normalize.sv.md) |
<!-- reading-navigation:end -->

> **Category: GUIDE. Scope: CURRENT (may also have legacy callers).** RTL is authoritative; diagrams use the [shared visual style](../../diagrams/diagram_style.md).

**Source:** [llm_attention_engine.sv](<../../../Verilog%20Source%20code/llm_attention_engine.sv>).

## At a glance

| Item | Description |
|---|---|
| Responsibility | Issue ordered K-cache reads for positions zero through the current causal position. The parent captures Q/K operands and issues shared SIMD operations. Each sum is rounded by RNE16, narrowed to S39, structurally multiplied by 11585, then rounded by RNE16 and clamped to S32. The engine owns 128 scores and the running maximum; softmax and value accumulation stay in the parent. |

## Architecture diagram

![llm_attention_engine.sv — overview](../../diagrams/previews/22_llm_attention_engine.sv_1.svg)

[Editable draw.io — llm_attention_engine.sv — overview](../../diagrams/architecture.drawio) · Page `22_llm_attention_engine.sv_1`.
