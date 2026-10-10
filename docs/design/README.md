# Design

<!-- reading-navigation:start -->
[Documentation](../README.md) → [02 · Architecture](../02-architecture/README.md) → This page

| Reading guide | Document |
|---|---|
| Read first | [System map](../01-system/README.md) |
| Continue / related lookup | [Module catalog](../source_guide/blocks/README.md) |
<!-- reading-navigation:end -->

> **Category: GUIDE.**

## Current llm_soc Design

| Order | Page | Content |
|---|---|---|
| 1 | [Full graph](full_rtl_language.md) | Model shape, inference steps, number format, and memory |
| 2 | [Host interface](host_interface.md) | Ports, memory map, handshake, reset, and execution sequence |
| 3 | [Throughput optimization](exact_throughput_optimization.md) | Cache, streaming, resource ownership, and traffic |
| 4 | [ASIC portability](asic_portability.md) | Logic portability and technology binding limits |
| 5 | [SRAM binding](asic_memory_binding.md) | Contract that must be maintained when replacing SRAM leaf |
| 6 | [RTL writing guidelines](rtl_style.md) | Clear hardware structure, register ownership, and coding policy |

After understanding the architecture, open the [module catalog](../source_guide/blocks/README.md)
or [NanoFable run guide](../demos/language.md).

## Legacy design

| Page | Scope |
|---|---|
| [Matmulfree architecture](<legacy/architecture.md>) | Core instruction-driven 32 PE; 32 KiB parameter and 8 KiB workspace |
| [Matmulfree ISA and interface](<legacy/interfaces.md>) | Opcode, descriptor, dynamic scale, and host map of old core |
| [Saved Hierarchy](<../source_guide/legacy/README.md>) | NORM flow, TMATMUL, vector operations, and legacy diagram |

The interfaces and capacity of the legacy core belong to top `matmulfree`, while
`llm_soc` uses a fixed graph and host map on a separate page above.

## Research and Decision

[Architecture research](<../history/architecture_research_20261005.md>) records the baseline and milestones
as stated in the document. [Review version 3](../reviews/rtl_change_review_v3.md)
records the implementation at the corresponding snapshot; [verification status](../verification/optimization_status.md)
indicates which evidence still applies to the workspace.
