# Quickstart

[Start here](README.md) · [Documentation map](../README.md)

| Step | Read | Outcome |
|---|---|---|
| 1 | [Architecture overview](../design/full_rtl_language.md) | Identify `llm_soc`, model geometry and inference flow |
| 2 | [Current verification status](../verification/optimization_status.md) and [execution contract](../NPU_V2_EXECUTION.md) | Identify matching evidence and the current milestone |
| 3 | [Server workflow](../../tools/server/README.md) | Follow connection, Slurm/X11, tool and library requirements |
| 4 | [Verification guide](../verification/README.md) | Select a scoped test, regression, synthesis or application stage |
| 5 | [Demo flow](demo-flow.md) | Prepare and evaluate a pretrained checkpoint |

On branch `remote`, the server workflow owns executable commands. Local
ModelSim/Questa/Verilator/Quartus instructions in older documents are historical.
Simulation, synthesis and pretrained-application results are separate gates;
use evidence matching the source/configuration being evaluated.
