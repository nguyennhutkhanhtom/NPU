# Glossary

[Start here](README.md) · [Fundamentals](fundamentals.md) · [Documentation map](../README.md)

This glossary gives the repository meaning of common terms. Where a module page
defines a more specific contract, that module page and its RTL take precedence.

| Term | Plain-language meaning |
|---|---|
| Accelerator | Hardware specialized for a workload; here it executes the language-model graph. |
| Activation | An intermediate model value produced while processing a token. |
| ASIC | A custom integrated circuit. ASIC evidence is separate from FPGA evidence. |
| Backpressure | A consumer temporarily refuses new data, so the producer must wait or queue it. |
| Bank | A memory slice that can be organized or accessed independently. |
| Checkpoint | Trained model parameters plus the metadata needed to interpret them. |
| Chunk | The subset of a vector or matrix row handled by one datapath transaction. |
| Clock edge | The instant when synchronous registers capture their next values. |
| Combinational logic | Logic with no stored transaction state; outputs follow current inputs. |
| Commit | The point where a write has actually changed the owned storage. |
| Context | Prompt and generated positions visible to the model; currently at most 128 positions. |
| Datapath | Arithmetic, memories, and value-routing hardware that performs computation. |
| Descriptor | Legacy metadata describing tensor address, length, format, and scale. |
| Drain | Allow already accepted work to finish or be safely discarded before reporting idle. |
| EDA | Electronic-design-automation tools used to simulate, synthesize, fit, and time hardware. |
| Elaboration | Resolving parameters, generate branches, widths, and module instances into a concrete design. |
| EOS | End-of-sequence token; generation may stop after it when minimum-length rules permit. |
| Evidence | Saved logs, manifests, hashes, and reports supporting a narrowly stated result. |
| Fmax | Highest clock frequency reported for the specified implementation and timing corner. |
| FPGA | Reprogrammable hardware used here for preserved implementation evidence. |
| FSM | Finite-state machine: registers and transition logic that sequence multi-cycle work. |
| Full graph | The current autonomous `llm_soc` transformer inference design. |
| Generate loop | Elaboration-time replication of hardware, not a runtime software loop. |
| Handshake | Signal rule defining when a request or response transfers ownership. |
| Host | External software/hardware that loads data, configures the NPU, starts it, and reads results. |
| In flight | Accepted work that has not yet reached its completion or cancellation point. |
| Lane | One parallel slice of a datapath or packed memory word. |
| Latency | Clock edges or time from an accepted input to its corresponding result. |
| Legacy | Preserved older design path; useful for history/regression but not the current application top. |
| Liberty | A standard-cell library file containing logic and timing models for ASIC synthesis/analysis. |
| LUT | In this repository, usually a lookup table of precomputed numeric values; in FPGA reports it can also mean a logic resource. |
| Manifest | Machine-readable record of inputs, hashes, commands, outputs, and tool context. |
| Memory macro | Technology-specific compiled SRAM block used behind a portable wrapper. |
| NPU | Neural processing unit: hardware organized for neural-network computation. |
| Overflow flag | Evidence that one or more values exceeded a supported range; exact behavior is operator-specific. |
| Parameter | Trained model value such as a weight, scale, or normalization gain. |
| Pipeline | Registers split a computation into stages so several transactions can overlap. |
| Portable RTL | Synthesizable logic that does not depend on a specific vendor cell or simulator feature. |
| Prefill | Processing existing prompt tokens to build model state before generating new tokens. |
| Ready/valid | Transfer protocol: an item is accepted on an edge where both signals are asserted. |
| Regression | A collection of tests rerun to detect unintended behavioral changes. |
| Reserved code | Bit pattern intentionally not representing normal data; ternary `10` is a format fault. |
| Reset | Returns control/validity to a known state; large memory payloads are not necessarily cleared. |
| Retire | Make an operation's result architecturally ordered and ready for its next owner. |
| RNE | Round to nearest, ties to even. This avoids a systematic preference in exact halfway cases. |
| RTL | Register-transfer level description of clocked state and combinational transfers. |
| Saturation | Clamp a result to the representable minimum or maximum instead of wrapping. |
| Sign extension | Widen a signed value by copying its sign bit into new high bits. |
| Signedness | Whether a bit vector represents only nonnegative values or two's-complement positive/negative values. |
| Simulation | Execute a model of the RTL over time and check observed behavior. |
| Slurm | Compute-cluster scheduler used to obtain an approved server allocation. |
| SRAM | Static random-access memory; large storage is isolated behind wrapper contracts. |
| STA | Static timing analysis: checks timed paths without simulating input vectors. |
| Synthesis | Convert RTL into a technology-mapped or generic gate-level implementation. |
| Tensor | Multidimensional array of model values. Hardware stores it as addressed rows and lanes. |
| Throughput | Rate at which a pipeline accepts inputs or produces outputs once operating steadily. |
| Tile | Smaller memory unit used repeatedly to implement a larger logical memory. |
| Timing corner | A specified process, voltage, and temperature condition for timing analysis. |
| Token | Integer vocabulary ID representing a text fragment; RTL does not store the text string. |
| Top | Root module selected for elaboration, simulation, or synthesis. The current graph top is `llm_soc`. |
| X11 | Display forwarding required by the approved server EDA launch flow. |

## Numeric notation used in this repository

| Notation | Meaning | Example |
|---|---|---|
| `S24` | Signed 24-bit two's-complement integer | Range `-2^23` through `2^23-1` |
| `U24` | Unsigned 24-bit integer | Range `0` through `2^24-1` |
| `S24/F16` | Signed 24-bit fixed-point value with 16 fractional bits | Stored `98304` represents `1.5` |
| `RNE16` | Round after removing 16 fractional bits, ties to even | Exact half chooses an even retained LSB |
| `E0`, `E1`, ... | Clock-edge-relative pipeline labels | Accepted at E0, result valid at a later named edge |
| `0x...` | Hexadecimal integer | `0x8000` is decimal 32768 |
