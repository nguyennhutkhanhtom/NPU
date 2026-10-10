# 03 · Model

[Documentation map](../README.md)

The hardware does not accept an arbitrary model file at runtime. Its graph shape,
memory capacities, numeric widths, and supported operators are fixed by RTL and
package constants. A checkpoint is compatible only when an exporter can map
every required tensor and tokenizer rule into those contracts.

Quantization is not merely file compression. It defines the integer codes,
scales, rounding, and saturation that the RTL executes. Two exporters using
slightly different rounding can produce different activations and eventually a
different selected token.

| Topic | Authoritative page | Scope |
|---|---|---|
| Model compatibility | [Supported models/exporter](../demos/candidates.md) | Checkpoint and graph compatibility requirements |
| Numerical formats | [Arithmetic contracts](../design/full_rtl_language.md#arithmetic-contracts) | Signedness, scaling, rounding and saturation |
| Context and memory | [Configuration and memory](../design/full_rtl_language.md#configuration-and-memory) | Model geometry, capacity and storage layout |
| Graph constants | [llm_pkg](../source_guide/blocks/llm_pkg.sv.md) | RTL owner of graph layout and constants |
| Checkpoint demo | [Demo flow](../00-start-here/demo-flow.md) | Preparation, current execution and evaluation pointers |
| Earlier model surveys | [Archive](../archive/README.md#legacy-core-and-demos) | Compatibility of the previous core |

Continue with [04 · Verification](../04-verification/README.md).

## Compatibility checklist in plain language

Confirm the number and shape of layers, hidden/feed-forward widths, vocabulary
and context limits, tokenizer IDs, ternary code mapping, per-row scales, and
normalization formats. Then confirm the packed addresses fit the documented
memory windows. Passing these checks means the data is representable; it still
needs reference and RTL verification.
