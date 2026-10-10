# 01 · System

[Documentation map](../README.md)

At system level, think of the repository as three cooperating parts. The host
loads bytes and requests a run. `llm_soc` controls the transformer graph and
shares arithmetic engines. Parameter, vector, and KV memories hold long-lived or
intermediate data. The current design is autonomous after start: it does not ask
software to execute each layer.

Read [the fundamentals](../00-start-here/fundamentals.md) first if clocked
hardware, fixed-point formats, or transformer terminology is unfamiliar.

| Topic | Authoritative page | Scope |
|---|---|---|
| Overview | [llm_soc architecture](../design/full_rtl_language.md) | Model geometry, graph and resource ownership |
| Block diagram | [Full RTL graph](../source_guide/full_graph.md#resource-and-data-path-diagram) | Top-level resources and data paths |
| Inference flow | [Inference sequence](../design/full_rtl_language.md#inference-flow) | Layer/operator sequence |
| RTL ownership | [Source guide](../source_guide/README.md) | Find the implementation owner |
| Diagram navigation | [Diagram index](../diagrams/README.md) | Editable sources, hierarchy variants and previews |
| Diagram catalog | [Architecture pages](../diagrams/architecture_catalog.md) | Individual system/module diagrams |
| Diagram cross-reference | [Diagram owners](../all_docs.md) | Links to documents containing diagrams |

Continue with [02 · Architecture](../02-architecture/README.md).

## Questions this section should answer

After following the links above, you should be able to explain where parameters,
prompt IDs, activations, KV data, and generated IDs live; which module sequences
operators; and why a memory response or arithmetic result is accompanied by a
valid/ready contract. Detailed signal ownership belongs to the architecture and
module pages, not to this overview.
