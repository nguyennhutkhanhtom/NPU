# Demos

<!-- reading-navigation:start -->
[Documentation](../README.md) → [03 · Model](../03-model/README.md) → This page

| Reading guide | Document |
|---|---|
| New to the subject | [NPU and RTL fundamentals](../00-start-here/fundamentals.md) · [Glossary](../00-start-here/glossary.md) |
| Read first | [Demo reading flow](../00-start-here/demo-flow.md) |
| Continue / related lookup | [Model compatibility](candidates.md) |
<!-- reading-navigation:end -->

> **Category: GUIDE.** Choose the execution flow before running a model.

A model demo is considered an RTL result only after the exported fixture, integer
reference, compiled source, run configuration, and returned token IDs all match.
Generating readable text by itself is not the gate. See [the fundamentals](../00-start-here/fundamentals.md#from-rtl-to-evidence)
for the distinction between application, simulation, synthesis, and timing
evidence.

| Demo | Purpose |
|---|---|
| [NanoFable language](language.md) | Run pretrained autonomous inference on `llm_soc` |
| [Supported model/exporter](candidates.md) | Check compatibility and requirements for changing checkpoints |
| [Legacy demos](legacy/README.md) | MNIST, CPU/RTL hybrid NanoFable and old model surveys |

Current verification and application status: [optimization status](../verification/optimization_status.md).
