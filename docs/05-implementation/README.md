# 05 · Implementation

[Documentation map](../README.md)

Implementation tools turn behavioral RTL into a concrete hardware structure.
Synthesis chooses gates or generic cells; FPGA fit places and routes resources on
an FPGA; ASIC implementation binds standard cells and SRAM macros for a target
process. Results from these targets answer different questions and must remain
separate.

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

## Reading timing and resource numbers

Always pair a number with its target, tool, constraints, corner, and source
snapshot. Fmax is not an intrinsic property of the algorithm. Area estimates can
change when memories are inferred as flip-flops instead of macros, and positive
setup slack does not imply that hold, recovery, removal, pulse-width, or
unconstrained-path checks passed. The status page records these fields together.
