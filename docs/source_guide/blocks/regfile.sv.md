# regfile.sv — 8 KiB SRAM Wrapper

<!-- reading-navigation:start -->
[Documentation](../../README.md) → [Archive · Legacy](../../archive/README.md) → [Module catalog](README.md)

| Reading guide | Document |
|---|---|
| New to the subject | [NPU and RTL fundamentals](../../00-start-here/fundamentals.md) · [Glossary](../../00-start-here/glossary.md) |
| Learn the RTL syntax | [How to read the SystemVerilog](../../00-start-here/reading-systemverilog.md) |
| Read first | [Legacy architecture](../../design/legacy/architecture.md) |
| Related implementation | [sram_256_wrapper.sv](sram_256_wrapper.sv.md) |
<!-- reading-navigation:end -->

> **Category: GUIDE. Scope: LEGACY.** RTL is authoritative; diagrams use the [shared visual style](../../diagrams/diagram_style.md).

**Status:** In use.

**Source:** [regfile.sv](<../../../Verilog%20Source%20code/regfile.sv>).

## At a glance

| Item | Description |
|---|---|
| Responsibility | This file maintains the private interface for the workspace but shares `sram_256_wrapper` with ADDR_W=8. The module is named `register`; the registers here are workspace SRAM, not an 8-vector register bank as the historical name might suggest. |

## Reading the `u_sram` instance line by line

`sram_256_wrapper #(.ADDR_W(8)) u_sram (` creates one permanent child hardware
instance. It is not a function call. `ADDR_W=8` makes the child address bus eight
bits wide and leaves its default depth at `1 << 8 = 256` rows. With 256 bits
(32 bytes) per row, this is `256 × 32 = 8192` bytes = 8 KiB.

The instance name `u_sram` identifies this child in hierarchy and simulation
waveforms. In `.rd_en(rd_en)`, the left name is the child port; the right name is
the parent signal. Direction comes from the child declaration:

| Connection | Hardware meaning |
|---|---|
| `.clk(clk)`, `.rst_n(rst_n)` | Both levels share the same clock/reset. Reset cancels control validity but does not erase workspace bits. |
| `.rd_en(rd_en)`, `.rd_addr(rd_addr)` | The active compute engine requests one 256-bit workspace row. |
| `.rd_data(rd_data)`, `.rd_valid(rd_valid)` | The child returns that row; the engine consumes it only when `rd_valid=1`. |
| `.wr_en(wr_en)`, `.wr_addr(wr_addr)`, `.wr_data(wr_data)` | The active compute engine writes all 256 bits of one row when `wr_en=1`. |
| `.host_en(host_en)`, `.host_we(host_we)` | The host requests access; `host_we=1` means write and `0` means read. |
| `.host_addr(host_addr)` | Bits `[10:3]` select one of 256 rows and `[2:0]` select one of eight 32-bit lanes. |
| `.host_wdata(host_wdata)` | The 32-bit value written into the selected lane. |
| `.host_rdata(host_rdata)`, `.host_rvalid(host_rvalid)` | Selected 32-bit lane and the indication that it belongs to the held host request. |

### What is stored in this RAM?

The storage holds raw packed bits, not a single permanently assigned data type.
Workspace descriptors give a base row, element count, format, and fractional-bit
count. Depending on the active instruction, a row can contain 32 S8 values,
16 S16/U16 values, or 8 S32 values. Regions may hold input/output activations,
NORM's quantized `q`, S24 scratch `z` stored in S32 cells, recurrent state/gates,
or logits. The RAM does not decode those meanings; the descriptor and consuming
datapath do.

See [How to read the SystemVerilog](../../00-start-here/reading-systemverilog.md)
for the same code example with syntax diagrams and enable tracing.

## Overview Architecture Diagram

![regfile.sv — overview](../../diagrams/previews/54_regfile.sv_1.svg)

[Editable draw.io — regfile.sv — overview](../../diagrams/architecture.drawio) · Page `54_regfile.sv_1`.

## Main flow

Compute read/write 256-word; host selects a 32-bit slice. The wrapper does not add FSM or change latency. Each port is connected one-to-one to the common implementation; see sram_256_wrapper to understand timing and write mask.

1. This is a wrapper workspace; module name `register` is kept for compatibility and is not the thesis register file pipeline.
2. Compute 8-bit address to select 256 256-bit words. Host address adds three bits to select eight 32-bit lanes.
3. The port is directly connected to `sram_256_wrapper`; the wrapper does not add storage, latency, or arbitration.
4. Read timing, mask write, and no-overlap rules are determined by the common implementation.

**RTL conventions.** The wrapper connects `host_rvalid` from the SRAM to the top. The backend receives read/address from the frontend and returns host_rvalid after two rising edges. The frontend top latches request/response, so the external host holds read/address for four rising edges until host_ready. The memory has eight 32-bit banks, with separate write-enable for each lane. The wrapper only connects ports, does not add registers or change latency. Simulation and synthesis use the same memory contract. See [implementation and SRAM diagram](sram_256_wrapper.sv.md).

## Important state / datapath groups

### [Lines 1–21: Two interfaces](<../../../Verilog%20Source%20code/regfile.sv#L1>)

**Purpose.** Compute address counts 256 words, host counts 32 words. Host byte address has its two alignment bits removed by the top.

**How this code works.** This group defines interfaces, widths, types, or intermediate signals. It creates a structure for later processing groups to use and does not itself represent a separate runtime step.

**Main signals and data.** `rd_en`: compute read request; `rd_addr`: word address to read; `rd_data`: read data word; `rd_valid`: valid read response; `wr_en`: compute write enable; `wr_addr`: word address to write; and 6 other auxiliary signals in the code segment.

### [Lines 22–47: SRAM instance and transparent port wiring](<../../../Verilog%20Source%20code/regfile.sv#L22>)

**Purpose.** `ADDR_W` determines row-address width and default depth. Named ports
transparently connect the workspace interface to the shared SRAM implementation.

**How the code works.** Elaboration creates one child instance. There is no
procedural call, local storage, or extra cycle in this wrapper. Storage,
write-mask selection, read tagging, and response latency belong to `u_sram`.

**Main signals and data.** `rd_en`: compute read request; `rd_addr`: word address to read; `rd_data`: read-out data word; `rd_valid`: valid read response; `wr_en`: compute write enable; `wr_addr`: word address to write; and 6 other auxiliary signals in the code segment.
