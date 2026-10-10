# sigmoid_257.mem — Hex version of the new sigmoid ROM

> **Category: GUIDE. Scope: CURRENT (may also have legacy callers).** RTL is authoritative; diagrams use the [shared visual style](../../diagrams/diagram_style.md).
[Documentation](../../README.md) → [Source guide](../README.md) → [File-by-file table of contents](README.md)

**Source:** [sigmoid_257.mem](<../../../Verilog%20Source%20code/sigmoid_257.mem>).

## Usage

Along with 257 samples at x=−8+i/16, raw=RNE(0x8000/(1+exp(−x))). Raw is stored in 16 bits with scale 2^−15. The exp formula is only used when creating the table. `sigmoid_lut.svh` is the constant ROM used in RTL; `sigmoid_257.mem` is the hex version for generator/test comparison. Do not load the hex file in the datapath. The current ROM does not use sigContent.mif.

