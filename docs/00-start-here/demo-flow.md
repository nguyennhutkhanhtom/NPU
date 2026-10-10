# Demo flow

[Start here](README.md) · [Documentation map](../README.md)

| Stage | Read | Question answered |
|---|---|---|
| Compatibility | [Model compatibility](../demos/candidates.md) | Can this checkpoint be represented by the current graph/exporter? |
| Preparation | [NanoFable guide](../demos/language.md) and [checkpoint assets](../../tests/language_demo/README.md) | Which model, tokenizer and export inputs are needed? |
| Execution | [Server application workflow](../../tools/server/README.md#application-checkpoint) | How is the prepared fixture run in the current backend? |
| Evaluation | [Verification status](../verification/optimization_status.md) | Which application results have matching evidence? |
| Capacity | [Model/context map](../03-model/README.md) | Which geometry, numeric and context limits apply? |

The NanoFable page preserves earlier local-run instructions and result-reading
details. Use the server workflow for current execution commands. A reference
export or completed runner alone does not establish a matching application PASS.

[Legacy demos](../archive/README.md#legacy-core-and-demos) cover the earlier
MNIST and CPU/RTL hybrid workflows.
