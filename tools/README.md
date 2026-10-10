# Support Tools

Run test/synthesis according to the [flow server](server/README.md); `timing` below is the backend/evidence FPGA history.

Tools prepare inputs, launch approved flows, validate diagrams, or collect
evidence; they are not themselves architecture owners. Before using a tool,
identify its input files, output location, and the claim its result supports.
The [fundamentals](../docs/00-start-here/fundamentals.md#from-rtl-to-evidence)
explain the difference between functional and implementation stages.


> **Category: GUIDE.**

[Project](../README.md) → **Tools**

| Folder | Task |
|---|---|
| [timing](timing/README.md) | Run Quartus, extract reports, and record timing evidence |
| [optimization](optimization/README.md) | Archive checkpoint and calculate RTL change ratio |
| [llm](llm/README.md) | Generate/check arithmetic table of the graph |
| [docs](docs/README.md) | Source guide tool and render documents/diagrams |

The diagram is holding an old snapshot; the docs update on 06/10/2026 has not been rendered yet or
edit diagram definitions. Only run the tool corresponding to the part that needs to be changed and
keep evidence/archive before creating new output.
