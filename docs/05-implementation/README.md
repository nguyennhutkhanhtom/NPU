# 05 · Implementation

[Documentation map](../README.md)

| Topic | Read | Scope |
|---|---|---|
| ASIC synthesis | [Server synthesis workflow](../../tools/server/README.md) | Slurm/X11, Genus, approved Liberty and reports |
| ASIC portability | [Technology boundaries](../design/asic_portability.md) | Portable logic and allowed implementation cells |
| SRAM integration | [ASIC memory binding](../design/asic_memory_binding.md) | SRAM functionality, timing and collision contracts |
| FPGA backend | [Quartus backend index](../../quartus/README.md) and [RAM leaf](../source_guide/blocks/quartus_word_ram.sv.md) | Preserved FPGA configuration and technology binding |
| FPGA timing evidence | [Timing index](../verification/timing/README.md) | Reading preserved full-top timing reports |
| Timing and area/resources | [Current verification/implementation status](../verification/optimization_status.md) | Matching Genus and FPGA results, with separate scopes |
| Previous implementation reports | [Archive](../archive/README.md#verification-and-implementation-snapshots) | Dated baselines, warnings and timing development |

Use the server workflow for current commands. Historical FPGA Fmax and Genus
timing reports are distinct evidence. These navigation entries add no new power
measurement or physical signoff claim.

Continue with [06 · Research](../06-research/README.md).
