# NPU and RTL fundamentals

[Start here](README.md) · [Glossary](glossary.md) · [Documentation map](../README.md)

This page supplies the background that the rest of the repository uses. It is
written for a reader who knows software or machine learning but may not yet know
digital hardware, SystemVerilog, fixed-point arithmetic, or EDA tools. You do not
need to memorize it before continuing; return here whenever a term is unfamiliar.

## What this repository builds

The project implements a small language model as synchronous digital hardware.
The current top-level module is `llm_soc`. A host computer first loads model
parameters and prompt token IDs, writes configuration registers, and starts the
design. The hardware then performs the complete inference graph and writes the
generated token IDs to an output buffer.

Three ideas are important:

1. **The host prepares and supervises.** It transfers data and starts a run, but
   it does not calculate each transformer operation for the RTL.
2. **The RTL owns inference.** Once started, `llm_soc` moves data through its
   memories and arithmetic engines according to a fixed graph.
3. **Token text exists outside the hardware.** The RTL works with integer token
   IDs. A tokenizer converts text to IDs before the run and IDs back to text
   afterward.

The older `matmulfree` top uses instructions and descriptors. It remains useful
for regression and design history, but it is not the current full-graph top.

## Hardware is not software executed line by line

SystemVerilog describes circuits. A register stores bits from one clock edge to
the next. Combinational logic continuously computes from its current inputs. A
module instance represents hardware that exists at the same time as every other
instance; it is not a function call that temporarily borrows a processor.

This changes how source code should be read:

- An `always_ff` block normally describes registers. Nonblocking assignments
  update those registers together at the clock edge.
- An `always_comb` block, `assign`, or pure combinational function describes
  logic whose output follows its inputs without owning transaction state.
- A `generate` loop creates repeated hardware at elaboration time. It does not
  mean one hardware unit executes a runtime loop repeatedly.
- An FSM, or finite-state machine, remembers which step of a multi-cycle
  operation is active. Its state transitions define the control sequence.

When documentation says a value is accepted at edge E0 and appears at E8, count
rising clock edges, not source-code statements. Other transactions may already
be following behind it in the same pipeline.

## Clock, latency, throughput, and pipeline

The clock provides shared moments when registers may capture new values.

- **Latency** is how long one accepted transaction takes to produce its result.
- **Throughput** is how often new transactions or results can be accepted after
  the pipeline is filled.
- **Pipeline stage** is a group of logic between registers.
- **Critical path** is the slowest register-to-register logic path that limits
  the maximum clock frequency.

A pipeline can have eight cycles of latency yet accept one new item every cycle.
That is not a contradiction: several independent items occupy different stages
simultaneously, like products on a factory line.

At 100 MHz one clock period is 10 ns. Passing a 100 MHz timing check means every
timed path in that implementation met the constraints for that report. It does
not by itself prove functional correctness, power, silicon signoff, or timing in
a different technology.

## Requests, acknowledgements, and backpressure

Interfaces need an unambiguous rule for when data changes ownership. In this
repository, names such as `valid`, `ready`, `start`, `busy`, `done`, and `ack`
describe that rule.

- `valid=1` means the producer is presenting a meaningful item.
- `ready=1` means the consumer can accept an item.
- A ready/valid transfer occurs only on a clock edge where both are 1.
- `busy=1` means a unit still owns in-flight work.
- `done` is usually a completion pulse; it should not be treated as stored state
  unless the specific interface says otherwise.
- A host acknowledgement means the addressed transaction reached the documented
  completion point. For writes, this can be later than request acceptance.

If the consumer lowers `ready`, the producer experiences **backpressure**. It
must retain the item or account for it in a queue; it must not silently drop or
reorder it. The source guide uses words such as *accepted*, *reserved*, *in
flight*, *retired*, and *drained* to distinguish these stages.

## Bits, signed values, and fixed-point numbers

Hardware signals have finite width. Width and signedness are therefore part of
the numerical contract, not incidental implementation details.

- `U24` means a 24-bit unsigned integer.
- `S24` means a 24-bit two's-complement signed integer.
- `S24/F16` means a signed 24-bit stored integer with 16 fractional bits. Its
  interpreted real value is `stored_integer / 2^16`.

For example, real value `1.5` in an `/F16` format is stored as
`1.5 × 65536 = 98304`. A stored value of `-32768` represents `-0.5`.

Operations often create a wider intermediate value. The design then explicitly
chooses how to return to the destination width:

- **Truncation** discards low or high bits according to the stated scale.
- **RNE** (round to nearest, ties to even) rounds halfway cases to the result
  whose least-significant retained bit is even.
- **Saturation** clamps a value to the smallest or largest representable value.
- **Wraparound** keeps only low bits; it is used only where the contract says so.

These choices affect model output. Replacing them with language-default casts or
ordinary floating-point calculations can change token selection even when the
formula looks mathematically similar.

## Tensors, rows, lanes, and packed words

A tensor is a multidimensional collection of numbers. Hardware stores it in
linear memories, so the documentation explains how tensor elements map to rows,
lanes, and addresses.

The current vector datapath has 32 lanes. One vector-memory row contains 32
signed 24-bit values, or 768 bits. A wider logical vector uses several rows. A
lane mask selects which lanes are written. Parameter memory uses 256-bit words
and exposes 32-bit lanes to the host.

Do not confuse these terms:

- A **lane** is one parallel slice of a datapath or memory word.
- A **row** is one addressed collection of lanes.
- A **bank** is an independently organized memory slice.
- A **tile** is a smaller physical/behavioral memory used to build a larger one.
- A **chunk** is the portion of an operation processed in one transaction.

## Why ternary weights are special

The linear layers store weights using two-bit ternary codes. The current code
mapping is `00 → 0`, `01 → +1`, and `11 → -1`; `10` is reserved and causes a
format fault. Multiplying by a ternary value therefore becomes select zero,
copy, or negate rather than a general runtime multiplication.

A dot product still adds many selected activation values. The accumulator is
wider than each input so intermediate sums do not overflow. A per-row scale is
then applied with explicit rounding and saturation to return to the activation
format.

## The transformer flow in plain language

The model processes one token position at a time.

1. **Embedding:** convert the token ID into a vector of numbers.
2. **RMS normalization:** rescale the vector to a controlled magnitude.
3. **Q, K, and V projections:** form query, key, and value vectors.
4. **RoPE:** rotate Q and K components so attention contains position
   information.
5. **Causal attention:** compare the current Q with cached K values from the
   current and earlier positions only, normalize the scores, and combine their V
   values.
6. **Residual and feed-forward path:** add the attention result, normalize again,
   calculate Gate/Up/Down projections, and add another residual.
7. **Language head:** score every vocabulary token.
8. **Selection:** choose the next token greedily or with seeded Gumbel sampling.

The selected token is fed back as the next input until EOS, the requested token
count, or the 128-position context limit is reached.

## Memories and reset

Reset clears control state and validity so old transactions cannot be mistaken
for new ones. Large SRAM payloads are intentionally not reset: clearing every
bit would add hardware and may prevent inference of a real memory macro. The
host must load required parameter and prompt data before starting.

A synchronous memory returns data after clock edges rather than immediately.
Wrappers add request tags, lane selection, tiling, and response-valid pipelines.
Consequently, a client must use the documented valid/acknowledgement signal; it
must not assume that data is ready a fixed number of source statements later.

## From RTL to evidence

Different tools answer different questions:

| Activity | Question answered | What it does not prove by itself |
|---|---|---|
| Elaboration/compile | Is the selected design structurally legal for this tool? | Numerical correctness or timing |
| Unit simulation | Does one block satisfy selected behavioral cases? | Whole-graph behavior |
| Graph regression | Does the integrated synthetic graph satisfy its assertions? | A real pretrained checkpoint |
| Application run | Do RTL token IDs match the integer reference for this fixture? | Timing or physical signoff |
| Synthesis | Can RTL map to the selected cell library, and what is the estimated structure? | Post-layout silicon timing |
| FPGA fit/STA | Does the fitted FPGA implementation meet its constraints? | ASIC timing |
| ASIC STA/signoff | Do the specified ASIC views meet signoff checks? | Functional coverage not exercised elsewhere |

A PASS claim is meaningful only with matching source, configuration, tool input,
and evidence hashes. An older PASS remains useful history but cannot verify
changed RTL.

## How to read the rest of the documentation

Use three layers instead of opening every file at once:

1. Read the [system architecture](../design/full_rtl_language.md) for the model
   shape and full inference flow.
2. Read the [full RTL graph](../source_guide/full_graph.md) to find the module
   that owns the behavior you care about.
3. Open that module guide and then the linked RTL around the named state or
   signal. Treat RTL as authoritative when a description and source disagree.

For an experiment, first read the relevant workflow and current evidence page.
Keep functional, application, synthesis, and timing claims separate. The
[glossary](glossary.md) provides short definitions for terms used across pages.
For source syntax and worked RTL examples, continue with [How to read the
SystemVerilog](reading-systemverilog.md).
