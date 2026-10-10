# sigmoid_257.mem — Hex version of the new sigmoid ROM

<!-- reading-navigation:start -->
[Documentation](../../README.md) → [02 · Architecture](../../02-architecture/README.md) → [Module catalog](README.md)

| Reading guide | Document |
|---|---|
| New to the subject | [NPU and RTL fundamentals](../../00-start-here/fundamentals.md) · [Glossary](../../00-start-here/glossary.md) |
| Learn the RTL syntax | [How to read the SystemVerilog](../../00-start-here/reading-systemverilog.md) |
| Read first | [Full RTL graph](../full_graph.md) |
| Related implementation | [sigmoid_lut.svh](sigmoid_lut.svh.md) |
<!-- reading-navigation:end -->

> **Category: GUIDE. Scope: CURRENT (may also have legacy callers).** RTL is authoritative; diagrams use the [shared visual style](../../diagrams/diagram_style.md).

**Source:** [sigmoid_257.mem](<../../../Verilog%20Source%20code/sigmoid_257.mem>).

## Usage

Along with 257 samples at x=−8+i/16, raw=RNE(0x8000/(1+exp(−x))). Raw is stored in 16 bits with scale 2^−15. The exp formula is only used when creating the table. `sigmoid_lut.svh` is the constant ROM used in RTL; `sigmoid_257.mem` is the hex version for generator/test comparison. Do not load the hex file in the datapath. The current ROM does not use sigContent.mif.

