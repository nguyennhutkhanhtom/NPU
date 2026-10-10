# Quickstart

[Start here](README.md) · [Documentation map](../README.md)

This page is a reading and workflow quickstart, not a command that runs every
tool automatically. Its purpose is to help you choose the smallest correct path
for your goal and avoid treating unrelated evidence as interchangeable.

If this is your first hardware project, read [the fundamentals](fundamentals.md)
before step 1. You should come away knowing the difference between a host and the
RTL, a simulation and synthesis result, and a functional PASS and timing PASS.

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

## Choose a path

- To understand the design without running tools, complete steps 1 and 2, then
  follow links from the architecture page to one module guide.
- To change RTL, complete steps 1 through 4. Start with the directly affected
  test; use the full regression only when shared behavior changed or the
  milestone requires it.
- To run a pretrained model, complete all five steps. A checkpoint export is an
  input preparation step, not proof that RTL produced matching tokens.
- To investigate timing, first identify the exact source/configuration hashes in
  the current status page. Timing from a different snapshot is only historical.

## Before accepting a result

Ask four questions: Which top module ran? Which source and configuration hashes
were used? Which tool/stage produced the result? Where is the matching manifest
or log? If any answer is missing, describe the result narrowly rather than
promoting it to a full-project PASS.
