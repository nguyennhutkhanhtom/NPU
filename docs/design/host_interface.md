# Host interface of llm_soc

<!-- reading-navigation:start -->
[Documentation](../README.md) → [02 · Architecture](../02-architecture/README.md) → This page

| Reading guide | Document |
|---|---|
| Read first | [System architecture](full_rtl_language.md) |
| Continue / related lookup | [Controller implementation](../source_guide/blocks/llm_soc.sv.md) |
<!-- reading-navigation:end -->

> **Category: GUIDE.**

Host and DUT use the same `clk`. All addresses below are byte addresses, aligned to
4 bytes. The matmulfree core has its own host contract in [legacy interface](<legacy/interfaces.md>).

## Ports

| Signal | Role |
|---|---|
| clk, rst_n | Clock and active-low reset |
| host_en, host_we | Has request; 1=write, 0=read |
| host_addr, host_wdata | Address and write data, each signal 32-bit |
| host_ready, host_rdata | ACK and 32-bit read data |
| running, ready | Graph running or idle, output via register |
| error, overflow_out | Graph/format/bounds error and saturation/overflow flag |
| pc_debug, instr_debug | 9-bit position and 13-bit phase/debug word |

## Memory map

| Window/register | Address | Content |
|---|---|---|
| Parameters | 0x00000000…0x000BFFFC | 768 KiB, 32-bit host lanes of 256-bit word |
| Prompt IDs | 0x00100000…0x001001FC | 128 slots; take lower 12 bits of word |
| Output IDs | 0x00200000…0x002001FC | Continuation IDs; read when graph is idle |
| Status | 0x00400000 | Running, ready, error, overflow and output count |
| Prompt count | 0x00400004 | Number of prompt tokens, write lower 8 bits; default 0 |
| Maximum new tokens | 0x00400008 | Maximum number of new tokens; default 96 |
| Start | 0x0040000C | Set bit 0=1 when idle |
| Temperature | 0x00400010 | U8/F8, default 166; 0 selects greedy |
| Random seed | 0x00400014 | Xorshift32 seed; 0 is changed to 1 |
| Minimum new tokens | 0x00400018 | Mask EOS before this count; default 64 |

Status uses bits 0=running, 1=ready, 2=error, 3=overflow and bits 11:4=output
count. Read only the registers/windows that RTL supports; do not assume config writes
have register readback. Graph owns KV and vector workspace.

## One transaction

![host_interface — overview](../diagrams/previews/07_host_interface_1.svg)

[Editable draw.io — host_interface — overview](../diagrams/architecture.drawio) · Page `07_host_interface_1`.


1. Set the address, write flag, and data; assert `host_en`.
2. Hold the request signals stable until `host_ready=1`.
3. For read, fetch `host_rdata` at ACK.
4. Deassert `host_en` for at least one clock and then start the next request.

Parameters are read synchronously via the adapter. Write ACK waits for leaf commit; time
ACK may vary between memory access and register access. Write during graph
running without changing parameters/config/prompt. Status is still used to poll progress.

Deasserting enable before the execution edge will cancel the write. After the write is accepted,
deasserting enable will cancel the response but the write can still be committed. Reset cancels the queue.
entry not yet committed and keeps the committed words; host should not assume rollback.

## Graph execution sequence

1. Reset and wait for internal reset release after two rising edges.
2. When idle, fully write parameter image through the parameter window.
3. Write prompt IDs in order, starting at 0x00100000.
4. Write prompt count, maximum new tokens, temperature, seed, and minimum new tokens.
5. Record START; polling status until graph is idle, check for errors and output count.
6. Read continuation IDs from the output window and then decode with the pinned tokenizer.

Launch conditions: prompt count >0, maximum new tokens >0 and their total ≤128.
Exporter limits new tokens to 1…127 and checks the tokenized prompt before
simulation. Select `MinNew ≤ NewTokens` in the demo to configure EOS understandably.

The testbench application has performed this host sequence. Use
[NanoFable guide](../demos/language.md) to run from PowerShell instead of manually writing the bus.
[Protocol and cancellation evidence](../verification/optimization_status.md) recorded
handshake, reset, and ACK cases have been verified.
