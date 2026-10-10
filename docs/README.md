# NPU documentation

Read from `00` to `06`, or choose a topic below. The current full-graph top is
`llm_soc`; `matmulfree` documentation belongs to the legacy core.

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
