# How to read the SystemVerilog in this repository

[Start here](README.md) · [NPU and RTL fundamentals](fundamentals.md) · [Glossary](glossary.md)

This page explains common source patterns using code that exists in this
repository. It is intended for readers who can follow programming logic but have
not yet learned how SystemVerilog describes hardware.

## A module instance creates hardware; it is not a function call

Consider the workspace wrapper in `regfile.sv`:

```systemverilog
sram_256_wrapper #(.ADDR_W(8)) u_sram (
    .clk(clk),
    .rst_n(rst_n),
    .rd_en(rd_en),
    .rd_addr(rd_addr),
    .rd_data(rd_data),
    .rd_valid(rd_valid),
    .wr_en(wr_en),
    .wr_addr(wr_addr),
    .wr_data(wr_data),
    .host_en(host_en),
    .host_we(host_we),
    .host_addr(host_addr),
    .host_wdata(host_wdata),
    .host_rdata(host_rdata),
    .host_rvalid(host_rvalid)
);
```

Read the first line from left to right:

- `sram_256_wrapper` is the type of submodule being instantiated.
- `#(...)` overrides compile/elaboration-time parameters of that submodule.
- `.ADDR_W(8)` replaces the default address width with 8 bits.
- `u_sram` is the unique name of this physical instance inside `register`.
- The following `(...)` list connects ports by name.

`ADDR_W=8` gives `2^8 = 256` addressed rows. Each row is 256 bits, or
32 bytes, so the capacity is `256 × 32 = 8192` bytes = 8 KiB. The wrapper's
default `DEPTH = 1 << ADDR_W` therefore becomes 256 without a second override.

The instance is present for the whole lifetime of the circuit. Calling code does
not “enter” and “return from” `u_sram`. Signals continuously connect the parent
and child, and state changes occur on clock edges according to the child RTL.

## Named port connections

For `.rd_en(rd_en)`, the name on the left is the child port and the expression on
the right is the signal in the parent module:

```text
parent register.rd_en ──> child u_sram.rd_en
parent register.rd_data <── child u_sram.rd_data
```

Direction comes from the child module declaration, not from visual left/right
placement in the instance. An input such as `rd_en` enters the child; an output
such as `rd_data` is driven by the child. Using the same name on both sides is a
convention that makes a transparent wrapper easy to audit; the two identifiers
still belong to different hierarchy levels.

The important ports in this example are:

| Port group | Meaning |
|---|---|
| `clk`, `rst_n` | Clock and active-low control reset. Reset cancels valid/control state; it does not clear all SRAM bits. |
| `rd_en`, `rd_addr` | Compute client requests one complete 256-bit row. `rd_en` is the request enable. |
| `rd_data`, `rd_valid` | Returned 256-bit row and the signal saying that row is meaningful now. |
| `wr_en`, `wr_addr`, `wr_data` | Compute client writes one complete 256-bit row when `wr_en=1`. |
| `host_en`, `host_we` | Host request enable and direction: read when `host_we=0`, write when `host_we=1`. |
| `host_addr` | Host address in 32-bit words. Low three bits select one of eight 32-bit lanes inside a 256-bit row. |
| `host_wdata` | One 32-bit host write value. |
| `host_rdata`, `host_rvalid` | One selected 32-bit read lane and its validity. |

An enable does not create a separate clock. It controls whether the associated
request or register update is active on the ordinary `clk` edge.

## What the two legacy RAM wrappers contain

The same generic `sram_256_wrapper` is configured in two ways:

| Parent module | Parameter | Capacity | Logical contents |
|---|---:|---:|---|
| `register` in `regfile.sv` | `ADDR_W=8` | 256 × 256 bit = 8 KiB | Runtime workspace: packed input/output tensors, quantized `q`, normalization scratch `z`, recurrent state, gates, or logits according to descriptors and the active instruction |
| `mem_mapping` | `ADDR_W=10` | 1024 × 256 bit = 32 KiB | Parameter storage: packed ternary weights, biases, embeddings, scales, or other model parameters according to the loaded program/layout |

The RAM itself does not know that bits represent `q`, a state vector, or a bias.
It only stores 256-bit rows. The descriptor, address, instruction, and consuming
datapath assign meaning to those bits. For example, one 256-bit workspace row can
hold 32 S8 values, 16 S16/U16 values, or 8 S32 values.

## `always_comb` describes combinational hardware

This write selector from `sram_256_wrapper.sv` is a useful example:

```systemverilog
always_comb begin
    write_address = wr_addr;
    write_data = wr_data;
    write_mask = {8{wr_en}};
    if (host_en && host_we) begin
        write_address = host_addr[ADDR_W + 2 : 3];
        write_data = {8{host_wdata}};
        write_mask = 8'b1 << host_addr[2:0];
    end
end
```

This does not run once per clock. It describes a mux whose outputs continuously
depend on current inputs:

1. The default path selects the compute write address and data.
2. `{8{wr_en}}` repeats `wr_en` eight times. If `wr_en=1`, mask `11111111`
   enables all eight 32-bit banks; if it is 0, no bank is written.
3. If `host_en && host_we` is true, the host path overrides the defaults.
4. `host_addr[ADDR_W+2:3]` removes the three lane-select bits and produces the
   256-bit row address.
5. `{8{host_wdata}}` copies the same 32-bit host value into all eight data lanes.
   Only one copy is committed because the mask is one-hot.
6. `8'b1 << host_addr[2:0]` moves a single `1` to the selected lane. That one mask
   bit is the write enable for its 32-bit bank.

The host branch has priority if both clients request a write, but this priority
is a safety property of the mux, not permission to use both clients together.
The parent controller's contract keeps host and compute transactions exclusive.

Every output is assigned before the `if`. Consequently all input combinations
have a defined value and synthesis does not need to infer a latch. In more
complex `always_comb` blocks, look for the same pattern: safe defaults first,
then state/opcode-specific overrides.

## `always_ff` describes registers updated on clock edges

Typical form:

```systemverilog
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        valid_q <= 1'b0;
    else
        valid_q <= request;
end
```

`valid_q` is stored state. It captures `request` on each rising clock edge. The
`negedge rst_n` term means asserting reset low clears it immediately. The `_q`
suffix conventionally identifies a registered value held from the previous
edge. Nonblocking assignment `<=` makes all registers in the clocked process
observe the old pre-edge values and update together.

Payload memories and wide datapath registers may intentionally have no reset.
They are safe only when a resettable valid bit prevents their stale value from
being consumed.

## Continuous assignment describes wiring or combinational equations

```systemverilog
assign rd_valid = read_valid_q && !response_host_q;
```

This creates an AND gate plus an inversion. It says the stored response is valid
for the compute port only when the response did not originate from the host. It
does not allocate another register or wait a cycle.

## Slices, concatenation, repetition, and indexed part-selects

| Syntax | Meaning |
|---|---|
| `x[7:0]` | Select bits 7 down to 0. |
| `{a, b}` | Concatenate `a` as higher bits and `b` as lower bits. |
| `{8{host_wdata}}` | Repeat `host_wdata` eight times. |
| `word[lane * 32 +: 32]` | Select 32 bits starting at `lane*32`, counting upward. |
| `value << amount` | Shift left; width is still governed by the left operand/expression rules. |
| `$signed(x)` | Interpret the existing bits as signed; it does not automatically add protective width. |
| `'0` | Fill the destination width with zero. |

Width must be traced explicitly. A mathematical value can overflow before being
assigned to a wider destination if the operands produced a narrower expression.
That is why arithmetic pages document extension, intermediate width, rounding,
and saturation separately.

## `generate for` creates repeated hardware

The SRAM wrapper uses a generate loop to create eight 32-bit RAM banks. `lane` is
an elaboration-time constant for each copy. The result is eight simultaneously
existing `banked_word_ram` instances, not one RAM called eight times at runtime.
Each copy receives the same row address but a different data slice and mask bit.

A procedural `for` inside `always_comb` also normally expands to parallel logic
when its bounds are static. It does not inherently mean one iteration per clock.
An FSM counter inside `always_ff` is what explicitly sequences work over cycles.

## How to trace an enable signal

When you see an enable such as `ws_rd_en` or `param_rd_en`, follow this sequence:

1. Find every assignment to the enable and identify which state/opcode can make
   it 1.
2. Find the module port or register that consumes it.
3. Pair it with its address/data signals; an enable without the corresponding
   payload does not explain the transaction.
4. Find the return validity or completion signal (`rd_valid`, `done`, `ready`, or
   `host_rvalid`).
5. Check how reset, cancellation, backpressure, and errors suppress or drain it.

For example, `wr_en` in `register` enables all eight workspace banks for one full
256-bit compute write. `host_en && host_we` instead enables exactly one bank via
the lane mask. `rd_en` captures a compute read request; the consumer must wait for
`rd_valid` before using `rd_data`.

## Where detailed explanations belong

Small wrappers, direct muxes, and non-obvious bit selections receive concise
source comments plus a module-guide explanation. Large FSMs and arithmetic
pipelines are documented primarily in their `.md` guide so the RTL continues to
show state ownership and timing clearly instead of becoming dominated by prose.
The module guide links exact source groups and explains what each enable, state,
payload, and completion signal means.
