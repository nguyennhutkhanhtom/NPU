# 02 · Architecture

[Documentation map](../README.md)

The controller, datapath and memory groups below are reading sections on one
page. Individual RTL guides remain in the flat [module catalog](../source_guide/blocks/README.md).

## Controller and host

| Topic | Read |
|---|---|
| Module hierarchy and ownership | [Full RTL graph](../source_guide/full_graph.md) |
| Host ports, commands and handshakes | [Host interface](../design/host_interface.md) |
| Graph control and operator sequencing | [llm_soc guide](../source_guide/blocks/llm_soc.sv.md) |
| Graph configuration and layout constants | [llm_pkg guide](../source_guide/blocks/llm_pkg.sv.md) |
| Architecture overview index | [Design index](../design/README.md) |

The instruction/descriptor ISA belongs to legacy `matmulfree`; see
[archived interfaces](../design/legacy/interfaces.md).

## Datapath

| Topic | Read |
|---|---|
| Ternary linear streaming | [Linear engine](../source_guide/blocks/llm_linear_engine.sv.md) and [ternary dot product](../source_guide/blocks/ternary_dot32.sv.md) |
| Attention score and normalization | [Attention engine](../source_guide/blocks/llm_attention_engine.sv.md) and [normalize](../source_guide/blocks/llm_attention_normalize.sv.md) |
| Vector/scalar arithmetic | [llm_math](../source_guide/blocks/llm_math.sv.md) and [arithmetic contracts](../design/full_rtl_language.md#arithmetic-contracts) |
| Vocabulary head | [Head engine](../source_guide/blocks/llm_head_engine.sv.md) |
| Shared helpers and LUTs | [Complete module catalog](../source_guide/blocks/README.md) |

## Memory and reset

| Topic | Read |
|---|---|
| Host memory map | [Memory map](../design/host_interface.md#memory-map) |
| Parameter/workspace/KV organization | [Configuration and memory](../design/full_rtl_language.md#configuration-and-memory) |
| Parameter storage and commit | [Parameter RAM](../source_guide/blocks/llm_parameter_ram.sv.md) |
| Vector/KV banks | [Bank RAM](../source_guide/blocks/llm_bank_ram.sv.md) |
| Memory pipeline and reset behavior | [Memory, pipeline and reset](../design/full_rtl_language.md#memory-pipeline-and-reset) |
| ASIC memory integration | [SRAM binding contract](../design/asic_memory_binding.md) |

Use the module catalog for remaining shared, helper, asset and legacy guides;
its scope column distinguishes their ownership. Continue with
[03 · Model](../03-model/README.md).
