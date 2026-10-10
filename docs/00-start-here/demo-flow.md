# Demo flow

[Start here](README.md) · [Documentation map](../README.md)

A demo crosses three different worlds: the original machine-learning
checkpoint, an integer reference model, and clocked RTL. The exporter translates
trained values into the exact packed formats expected by hardware. The reference
calculates expected token IDs with the same integer rules. The application test
loads those assets into `llm_soc` and compares the RTL output IDs with the
reference; text decoding happens afterward.

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

## What can go wrong at each stage

| Stage | Typical mismatch | Why it matters |
|---|---|---|
| Compatibility | Wrong tensor shape, tokenizer, vocabulary, or unsupported quantization | The checkpoint cannot map to the fixed hardware graph |
| Preparation | Stale or partially generated fixture | RTL and reference may receive different bytes |
| Execution | Wrong top, RAM binding, source snapshot, or simulator setup | The run does not represent the intended design |
| Evaluation | Comparing text only instead of token IDs and provenance | Decoding can hide the first numerical divergence |

When debugging, preserve the first mismatching token, its input configuration,
the reference output, and the run manifest. Do not change expected values or
timeouts merely to obtain a PASS.
