# Models compatible with llm_soc

> **Category: GUIDE.**

[Documentation](../README.md) → [Demo](README.md) → **Model compatibility**

## Models currently supported by the exporter

The exporter currently pins **NanoFable-1M-ternary seed1** using SHA-256, with four layers,
128 channels, four heads, FFN 384 channels, and a vocabulary of 4,096. The architecture uses affine
RMSNorm, RoPE, causal attention, SwiGLU, and tied embedding/head. Maximum RTL context
128 positions; the total prompt tokens and newly requested tokens must stay within this limit.

| Data | Export method |
|---|---|
| Embedding and tied head | S8 codes, scale each row separately U24/F24 |
| Seven ternary matrix per layer | Keep three levels -1/0/+1; 2-bit code and trained scale |
| RMSNorm gain | S16/F12 |
| Activations and KV | S24/F16 according to integer reference |
| Tokenizer | tokenizer.json pinned, token ID 12 bit |

Full graph memory is 768 KiB for parameters, 384 KiB for KV, and 9 KiB for vector workspace.
[Configuration and format](../design/full_rtl_language.md) describe the detailed contract.

## What is needed to replace the checkpoint?

The current CLI can change prompt, number of tokens, temperature, seed, and minimum token.
It does not yet have a parameter to select any checkpoint: exporter checks the file SHA
model and requires geometry/operators already supported.

To add another checkpoint, it is necessary to reconcile tensor names, shape, ternary encoding,
normalization, positional encoding, tokenizer, and memory layout; then update
exporter/reference and verify arithmetic. If the geometry or operator changes on
RTL, new evidence unit/graph and timing are required before the application.

Checkpoint seed0 with the same architecture is another training replica. Having a seed0 file
in upstream metadata does not prove it has been exported or run on RTL.
Numeric matching of a checkpoint also does not prove conversational capability
or quality on the dataset.

## Old survey document

[Survey models for core 32 PE](legacy/model_candidates.md) keep the calculations
MNIST/MLGRU/Char32 and 32+8 KiB capacity of the matmulfree architecture. Use the document
within the legacy scope; choose the current NanoFable according to the above instructions.
