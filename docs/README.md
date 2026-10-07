# NPU documentation

> **Category: GUIDE.** Start here to choose the smallest relevant document.

## Start here

| I want to know? | Read |
|---|---|
| How the current NPU works | [Current architecture](design/full_rtl_language.md) |
| How RTL is divided into blocks | [Full RTL graph](source_guide/full_graph.md) |
| Current verification/status | [Verification status](verification/optimization_status.md) |
| How to verify the design | [Verification guide](verification/README.md) |
| How to run the language demo | [NanoFable guide](demos/language.md) |
| RTL coding policy | [RTL style](design/rtl_style.md) |
| Historical work | [History](history/README.md) |

`llm_soc` runs the language graph in RTL; the host loads parameters/configuration/prompt IDs and decodes output IDs. `matmulfree` is the legacy instruction-driven core.

[Design](design/README.md) ? [Source guide](source_guide/README.md) ? [Demos](demos/README.md) ? [Reviews](reviews/README.md) ? [Diagrams](diagrams/README.md)
