# sram_256_wrapper.sv — Synchronous SRAM with 32-bit mask

<!-- reading-navigation:start -->
[Documentation](../../README.md) → [Archive · Legacy](../../archive/README.md) → [Module catalog](README.md)

| Reading guide | Document |
|---|---|
| Read first | [Legacy architecture](../../design/legacy/architecture.md) |
| Related implementation | [banked_word_ram.sv](banked_word_ram.sv.md) |
<!-- reading-navigation:end -->

> **Category: GUIDE. Scope: LEGACY.** RTL is authoritative; diagrams use the [shared visual style](../../diagrams/diagram_style.md).

**Status:** In use — shared for parameters and workspace.

**Source:** [sram_256_wrapper.sv](<../../../Verilog%20Source%20code/sram_256_wrapper.sv>).

## At a glance

| Item | Description |
|---|---|
| Responsibility | Compute reads/writes 256-bit words; host reads/writes a 32-bit lane. `ADDR_W=8` creates an 8 KiB workspace, `ADDR_W=10` creates a 32 KiB parameter; `llm_soc` uses `ADDR_W=15, DEPTH=24576` for 768 KiB. Eight 32-bit banks use the same synchronized read address and separate write-enable by mask; each bank is divided into tiles up to 1024 words in [banked_word_ram](banked_word_ram.sv.md). The RTL has one implementation for simulation and synthesis, with no defines or vendor-specific attributes. Leaf tiles are the boundary for replacement with Quartus IP or ASIC SRAM adapter. |

## Overall Architecture Diagram

![sram_256_wrapper.sv — overview](../../diagrams/previews/64_sram_256_wrapper.sv_1.svg)

[Editable draw.io — sram_256_wrapper.sv — overview](../../diagrams/architecture.drawio) · Page `64_sram_256_wrapper.sv_1`.

Solid lines represent data; dashed lines represent address, enable, and valid. The RAM box describes storage logic, not specifying a physical SRAM macro or block RAM. Reset only clears control/tag; data is only used when valid.

## Main flow

1. The top ensures the host and compute do not access simultaneously. Host write selects one 32-bit lane; compute write selects all eight lanes.
2. The first rising edge latches the read request, address, client, and lane. The next rising edge reads the word into `read_row_q` and transfers tag/valid to the response. Two clients use the same contract of the two rising edges.
3. Compute the 256-bit word consumption when `rd_valid=1`. The host port of the adapter holds `host_en=1`, `host_we=0`, and the destination address `host_rvalid=1`. The frontend latches requests and responses, so the external host receives `host_ready` after four rising edges; adapter latency is still two edges.
4. The host validates the current request, request tag, and response tag in the same row/lane and client. Changing the address, writing, or idling makes the old response invalid; reading the same address after a write still has to wait.
5. RAM and data registers do not have asynchronous reset and do not have an initialization loop. Reset only clears the tag/control. The host must load data before reading; data when valid=0 cannot be used.
6. When replacing storage with an SRAM macro, the adapter must maintain a 32-bit mask, read/valid contract, arbitration, and reset control. Leaf read/write to the same address on one edge returns old-data. The wrapper's read request latches on the edge before the leaf read: a collision is defined at the edge where the leaf is actually read, not at the edge where the wrapper request is received. Unit tests verify tile boundaries and collisions; the contents are not reset.

## Important state / datapath groups

The sections below cover the full literal current source, in line order.

### [Lines 1–25: Interface and internal write ports](<../../../Verilog%20Source%20code/sram_256_wrapper.sv#L1>)

**Purpose.** Expose two clients and word size; host address is a 32-bit word index, consisting of a row and three lane bits.

**Main signals.** `ADDR_W`, `DEPTH`, `rd_en/rd_addr/rd_data/rd_valid`, `wr_en/wr_addr/wr_data`, `host_en/host_we/host_addr/host_wdata/host_rdata/host_rvalid`. Three signals `write_address`, `write_data`, `write_mask` connect the write mux with the banks.

### [Lines 26–41: Address mux and write mask](<../../../Verilog%20Source%20code/sram_256_wrapper.sv#L26>)

**Operation.** Default selects compute write, mask is eight copies `wr_en`. Host write selects row from `host_addr[ADDR_W+2:3]`, replicates 32-bit data to eight lanes, and sets one mask bit from `host_addr[2:0]`. Each bank only receives data when the corresponding mask bit is 1. Defaults are fully assigned in `always_comb`, no latch is created.

### [Lines 42–60: Reading data and checking response](<../../../Verilog%20Source%20code/sram_256_wrapper.sv#L42>)

**How it works.** `read_row_q` drives compute data; the response lane selects 32-bit host data. Compute valid chooses response not from host. Host valid also checks current enable/read and both tags in the same row/lane, preventing old data from being received after a different request.

**Main signals.** `read_pending_q/read_host_q`, `shared_read_address_q/read_lane_q`, `read_valid_q/response_host_q`, `response_address_q/response_lane_q`, `read_row_q`.

### [Lines 61–75: Eight banks synchronous read and full word write](<../../../Verilog%20Source%20code/sram_256_wrapper.sv#L61>)

**How it works.** `generate` creates eight independent banks during elaboration; the lane index is constant. Each bank writes a full 32-bit word with a separate enable and latches a slice of `read_row_q` from the shared read address. RAM and the read data register only use `posedge clk`, allowing the storage to be mapped via the corresponding flow synthesis.

**Points to read carefully.** `rst_n` only gates writes in the memory process. It does not erase memory or data output; the reset control underneath removes old valid signals.

### [Lines 76–101: Request, response tag, and reset control](<../../../Verilog%20Source%20code/sram_256_wrapper.sv#L76>)

**How it works.** Reset clears pending/valid and tag. Each edge transfers the request tag to the response, while also latching a new request host read or compute read. When there is no read, pending goes back to zero. The host has priority in the mux, but the caller must ensure arbitration according to the contract; this priority does not support two simultaneous transactions.

#### Hardware block diagram of the group

![sram_256_wrapper.sv — detail 1](../../diagrams/previews/65_sram_256_wrapper.sv_2.svg)

[Editable draw.io — sram_256_wrapper.sv — detail 1](../../diagrams/architecture.drawio) · Page `65_sram_256_wrapper.sv_2`.

`read_row_q` only has clock and capture enable. Tag/valid ensures the client does not consume invalid data.
