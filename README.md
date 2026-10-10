# NPU ternary: full graph LLM on RTL

**Current flow:** [Xcelium/Genus on Linux Slurm](tools/server/README.md). Local backends have stopped functioning on branch `remote`.


> **Category: GUIDE.**

The top is [`llm_soc.sv`](<Verilog Source code/llm_soc.sv>). The host loads the checkpoint,
configures and prompts; RTL runs prefill, four transformer layers, language head,
selects token and the next token generation loop. `matmulfree.sv` is core instruction-driven
kept for design and regression legacy.

**Start at [documentation table of contents](docs/README.md)** or
**[NanoFable run guide](docs/demos/language.md)**.

## Read as needed

| What you need to do? | Page to read |
|---|---|
| Understand the current design | [llm_soc Architecture](docs/design/full_rtl_language.md) |
| Load data and control top | [Host interface](docs/design/host_interface.md) |
| Find modules and read RTL | [Blocks of the full graph](docs/source_guide/full_graph.md) |
| Run a real checkpoint | [Step-by-step NanoFable Demo](docs/demos/language.md) |
| Check source, timing, and results | [Verification status](docs/verification/optimization_status.md) |
| Look up old cores | [Legacy documentation](docs/design/README.md#legacy-design) |

## Architecture and verification

[Current architecture](docs/design/full_rtl_language.md) owns model geometry and numerical contracts. [Current verification and implementation status](docs/verification/optimization_status.md) owns checkpoint results and evidence.

## Repository layout

| Location | Content |
|---|---|
| [Verilog Source code](<Verilog Source code/README.md>) | RTL and LUT used for compilation |
| [docs](docs/README.md) | Architecture, instructions, verification, review, and history |
| [tests](tests/README.md) | Testbench, reference, and runner |
| [quartus](quartus/README.md) | Backend configuration; old project in archive |
| [tools](tools/README.md) | Documentation, timing, LUT, and checkpoint tools |

The Quartus results are evidence for this backend EDA; ASIC requires SRAM binding,
library and separate signoff process. [AGENTS.md](AGENTS.md) records RTL rules;
[TASK_STATE.md](TASK_STATE.md) leads to checkpoints and pending work.
