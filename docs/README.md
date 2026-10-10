# NPU documentation

Read from `00` to `06`, or choose a topic below. The current full-graph top is
`llm_soc`; `matmulfree` documentation belongs to the legacy core.

If you are new to digital hardware, start with [NPU and RTL fundamentals](00-start-here/fundamentals.md)
and keep the [glossary](00-start-here/glossary.md) nearby. The documentation does
not require prior knowledge of SystemVerilog, fixed-point arithmetic, transformer
hardware, or EDA terminology; those two pages explain the shared foundations so
specialist pages can focus on their exact contracts.

## Reading map

```text
docs/README.md
├── 00-start-here/      Setup and demo entry points
├── 01-system/          Overview, block diagrams, inference flow
├── 02-architecture/    Controller, datapath, memory, module reference
├── 03-model/           Compatibility, numeric formats, context limits
├── 04-verification/    Test workflow, application gates, evidence
├── 05-implementation/  ASIC, FPGA history, timing and resources
├── 06-research/        Optimization rationale and measurements
├── decisions/         Execution contract and design reviews
└── archive/           Historical checkpoints and legacy documents
```

This is a navigation hierarchy. Each folder has a small index linking to the
existing authoritative pages. Source guides, diagram assets and evidence stay
at their original paths because documentation tools and manifests reference
them. No parallel copies of architecture or verification claims are created.

| Topic | Start here | What you will find |
|---|---|---|
| 00 · Start here | [Quickstart and demo](00-start-here/README.md) | Setup, current server flow, checkpoint workflow |
| 01 · System | [System map](01-system/README.md) | Overview, diagrams, inference sequence |
| 02 · Architecture | [Architecture map](02-architecture/README.md) | Host/controller, compute engines, memory, flat module catalog |
| 03 · Model | [Model map](03-model/README.md) | Supported models, arithmetic contracts, memory/context limits |
| 04 · Verification | [Verification map](04-verification/README.md) | Regression, module tests, application gates, status |
| 05 · Implementation | [Implementation map](05-implementation/README.md) | ASIC flow, SRAM binding, FPGA evidence, timing/resources |
| 06 · Research | [Research map](06-research/README.md) | Optimization proposals, reviews and measured comparisons |
| Decisions | [Decisions and reviews](decisions/README.md) | Execution contract, RTL policy and review snapshots |
| Archive | [Historical and legacy map](archive/README.md) | Earlier development, demos, reviews and baselines |

## Direct lookups

Choose a reading route based on your task; each page links back to its topic.

| Goal | Reading order |
|---|---|
| Learn from the beginning | [Fundamentals](00-start-here/fundamentals.md) → [Glossary](00-start-here/glossary.md) → [System overview](design/full_rtl_language.md) |
| Understand the hardware | [System overview](design/full_rtl_language.md) → [Full RTL graph](source_guide/full_graph.md) → [Module guides](source_guide/blocks/README.md) |
| Run a checkpoint | [Quickstart](00-start-here/quickstart.md) → [Model compatibility](demos/candidates.md) → [Demo flow](00-start-here/demo-flow.md) → [Application evidence](verification/optimization_status.md) |
| Change or evaluate RTL | [Architecture map](02-architecture/README.md) → [RTL policy](design/rtl_style.md) → [Verification workflow](verification/README.md) → [Implementation evidence](verification/optimization_status.md) |
| Review optimization decisions | [Execution contract](NPU_V2_EXECUTION.md) → [Research map](06-research/README.md) → [Reviews](decisions/README.md) → [Measured results](verification/optimization_status.md) |

| Need | Authoritative page |
|---|---|
| Current architecture and numeric contracts | [Full RTL language](design/full_rtl_language.md) |
| Current verification and implementation evidence | [Verification status](verification/optimization_status.md) |
| Active execution milestones | [NPU v2 execution contract](NPU_V2_EXECUTION.md) |
| Run tests or synthesis on branch `remote` | [Server workflow](../tools/server/README.md) |
| Find an individual RTL/LUT guide | [Module catalog](source_guide/blocks/README.md) |
| Find an editable diagram | [Diagram catalog](diagrams/architecture_catalog.md) |

Existing specialist indexes remain available: [design](design/README.md),
[source guide](source_guide/README.md), [demos](demos/README.md),
[reviews](reviews/README.md), [diagrams](diagrams/README.md),
[diagram references](all_docs.md), and [history](history/README.md).

For new documentation, use the relevant topic index and link to one owner page.
Keep module guides in `source_guide/blocks/`; keep evidence and historical
snapshots in their existing locations. Extend tables rather than adding deep
folder trees. A topic without an owner page should not imply a completed design,
benchmark, power analysis or signoff result.
