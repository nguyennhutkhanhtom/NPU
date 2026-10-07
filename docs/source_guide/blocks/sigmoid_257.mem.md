# sigmoid_257.mem — Bản hex của ROM sigmoid mới

> **Category: GUIDE. Scope: CURRENT (may also have legacy callers).** RTL is authoritative; diagrams are preserved from the existing guide.
[Tài liệu](../../README.md) → [Source guide](../README.md) → [Mục lục từng file](README.md)

**Source:** [sigmoid_257.mem](<../../../Verilog%20Source%20code/sigmoid_257.mem>).

## Cách sử dụng

Cùng 257 mẫu tại x=−8+i/16, raw=RNE(0x8000/(1+exp(−x))). Raw lưu 16 bit và có scale 2^−15. Công thức exp chỉ dùng lúc tạo bảng. `sigmoid_lut.svh` là ROM hằng dùng trong RTL; `sigmoid_257.mem` là bản hex để generator/test đối chiếu. Không load file hex trong datapath. ROM hiện tại không dùng sigContent.mif.

