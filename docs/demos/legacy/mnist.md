# Demo checkpoint BitNetMCU on NPU

<!-- reading-navigation:start -->
[Documentation](../../README.md) → [Archive](../../archive/README.md) → This page

| Reading guide | Document |
|---|---|
| Read first | [Legacy architecture](../../design/legacy/architecture.md) |
| Continue / related lookup | [Current evidence](../../verification/optimization_status.md) |
<!-- reading-navigation:end -->

> **Category: LEGACY.**

Ran the model **Binary-MNIST width160_160_160** recommended in the [model list](<../candidates.md>), using publicly trained weights. Actual graph is **256→160→160→160→10**, three ReLUs, RMSNorm without affine before each linear layer; no bias. RTL uses the portable version after timing optimization; [design review](<../../history/reviews/design_review.md>) recorded new register boundaries.

## Results

Demo run on **01/10/2026 at 14:30:25** passed **22,492 commands / 12,402 host comparisons**, compiled and simulated with **0 errors / 0 warnings**.

| Check | Result |
|---|---|
| Original PyTorch model on CPU | 10/10 sample images correctly labeled |
| Integer reference after export | 10/10 correct labels, same predictions as CPU |
| RTL running exported graph | 10/10 correct labels, no error/overflow |
| Intermediate data | 40 layer passes: output, q, z, D, NORM/QUANT coefficients bit-exact matches with integer reference |
| Whole graph program | 12 instructions including HALT; run twice, second run without reset/reload |
| Whole graph processing cycles | 20,783 clocks for each full graph run of image #0; host load/readback not included |

![Sample image, label, and CPU/RTL prediction](<../mnist.png>)

These are **10 preprocessed 16×16 images** from the upstream sample header, not accuracy measurements on the entire MNIST. Bit-exact applies between RTL and integer reference; activations are not required to be bit-identical with the original float32 model. 10 ns clock in the testbench does not verify ASIC timing.

## Checkpoint and conversion method

- [Checkpoint and current code pinned to commit](https://github.com/cpldcpu/BitNetMCU/tree/0715bfc4ed9f2578496e17b4b0e13f2297e3cc0f/modeldata).
- [Graph/quantizer at commit adding checkpoint](https://github.com/cpldcpu/BitNetMCU/blob/1e06ef3b3c028aac516dc7ad7607cfe61af31320/BitNetMCU.py).
- [Header containing sample data](https://github.com/cpldcpu/BitNetMCU/blob/0715bfc4ed9f2578496e17b4b0e13f2297e3cc0f/BitNetMCU_MNIST_test_data.h).
- SHA-256 checkpoint: `cd1573f0bfd7f4b1bc734601d98c9df122a2a8fedf41066f4ba9bd17ac4af289`.

Exporter reads tensor metadata using a restricted pickle reader and strictly loads four tensors into the historical graph. The CPU runs the main PyTorch implementation, with PyTorch **2.5.1+cpu** and one thread. Runtime/dependency is installed separately in `tests/model_demo/packages`, without modifying the general Python environment.

Weight uses float32 quantizer `sign(w−mean(w))`; gain of each layer `mean(abs(w))` is stored in M/r of the dynamic descriptor. There is a correct weight at the mean so it carries a zero code. Code −1/0/+1 is packed `11/00/01`, not using BitNetMCU's original packing format. Hidden state uses **S16/F9**, logits **S32/F16**; input S8 is sign-extended to S16. NORM uses epsilon=0 and delta=1 for this demo.

Host only loads weight, input, descriptor, and instruction; does not write q/z/hidden values from reference. Ten images run with HALT after each layer to observe all 40 outputs and metadata. A program continuously runs the entire graph on image number 0 twice to check scheduler/restart and final results without intervention between layers.

## Memory

| Region | Use / capacity |
|---|---|
| Weight | 980 word × 256 bit = **31,360/32,768 byte**, remaining 1,408 byte |
| Allocated workspace payload | **2,496 byte** |
| Highest workspace address | Byte 5,119; area extends to **5,120/8,192 byte** due to fixed base |
| Instruction | **12/512 word**, of which 11 engine instructions and one HALT |

Full parameter image includes 1,024 word, fill zeros in the remaining part; upload uses 8,192 host write 32 bit. The number of inference cycles above is separate from host load/read. Bias does not take up SRAM because checkpoint has no bias; descriptor and runtime scale are in core registers.

## Historical Evidence

[README snapshot](<../../../tests/model_demo/README.md>) records the removal of runner/exporter/testbench
legacy. [results.json](<../../../tests/model_demo/results.json>) keeps checkpoint, tool version,
source/asset hashes, predictions, checks and cycles. The images
[parameter.mem](<../../../tests/model_demo/parameter.mem>), [program.mem](<../../../tests/model_demo/program.mem>),
[program_layout.json](<../../../tests/model_demo/program_layout.json>) and
[cpu_reference.json](<../../../tests/model_demo/cpu_reference.json>) keep layout/reference for lookup.
This is a legacy demo, not a gate or application of full `llm_soc`.

---

[Other demos](<../README.md>) · [Architecture and memory](<../../design/legacy/architecture.md>) · [About the document index](<../../README.md>)
