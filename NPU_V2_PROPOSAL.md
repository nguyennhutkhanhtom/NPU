> **Reader note:** This is a proposal, not proof that every described phase is
> implemented. Read [NPU and RTL fundamentals](docs/00-start-here/fundamentals.md)
> for background, then consult the [execution contract](docs/NPU_V2_EXECUTION.md)
> and [current evidence](docs/verification/optimization_status.md) for status.

I completed the architectural reassessment against the active RTL. I did **not modify any RTL**. The active full-language design is `llm_soc`; the source guide identifies `llm_soc.qsf` as the full-top Quartus flow, while the instruction-driven `matmulfree` path is legacy/supporting RTL. Pasted text

I use the requested labels throughout:

- **OBSERVED** — directly visible in RTL.
- **INFERRED** — architectural consequence of the RTL.
- **PROPOSED** — NPU v2 recommendation.
- **NEEDS MEASUREMENT** — RTL supports the conclusion but no measured counter/synthesis value was supplied.

---

# 1. Current architecture reconstructed

**OBSERVED.** The current machine is a fixed NanoFable inference accelerator: 4 transformer blocks, hidden dimension 128, four 32-channel heads, context 128, and a 24-bit activation datapath. The package hard-codes the context and parameter-memory map. Pasted text

The top controller has two distinct sequencing layers:

```text
Host
 │
 ├── Prompt/config registers
 └── Parameter loading
          │
          ▼
+-------------------------------+
| llm_soc                       |
|                               |
| Graph FSM                     |
| EMBED → ANORM → Q → K → V     |
| → RoPE Q/K → KV → ATTENTION   |
| → O → residual                |
| → MNORM → GATE → UP → SiLU    |
| → gate*up → DOWN → residual   |
| → ... layers ...              |
| → FNORM → LM HEAD → token     |
|                               |
| 112-state operation FSM       |
+----------+----------+---------+
           |          |
           |          +---------------------+
           ▼                                ▼
 +--------------------+             +------------------+
 | Parameter RAM      |             | Vector scratch   |
 | 24576 × 256 bit    |             | 96 × 768 bit    |
 | ≈ 768 KiB          |             | ≈ 9 KiB          |
 +---------+----------+             +------------------+
           |
       +---+-----------------------------+
       |                                 |
       ▼                                 ▼
+---------------+                  +-------------+
| linear_engine |                  | llm_math    |
| ternary_dot32 |                  | 32 lanes    |
+---------------+                  +------+------+ 
                                           |
                         +-----------------+----------------+
                         |                 |                |
                         ▼                 ▼                ▼
                    Attention          LM head         Norm/RoPE/
                                                       vector ops

                  +----------------------+
                  | KV cache             |
                  | 4096 × 768 bit       |
                  | ≈ 384 KiB            |
                  +----------------------+
```

The graph states themselves explicitly serialize `EMBED → ANORM → Q → K → V → ... → HEAD`. Pasted text

The principal architectural blocks are:

| Block | Purpose / storage / parallelism | Main dependency |
|---|---|---|
| `llm_soc` | Global graph + 112-state micro-operation controller | Completion-driven `op_done` |
| `llm_linear_engine` | Ternary matvec row engine; 32-element ternary dot pipeline | Parameter RAM + input cache |
| `llm_math` | 32 parallel 24×32-bit multiplies plus reduction | Shared by attention, head, norm/vector paths |
| `llm_attention_engine` | Streams Q·K scores | KV cache + `llm_math` |
| Parent attention FSM | exp/softmax, value accumulation | Score memory, KV, `llm_math` |
| `llm_attention_normalize` | 32 output divisions, 4 lanes default | Sequential 64-cycle dividers |
| Norm path | RMSNorm-like square → sqrt → reciprocal → scale | `llm_math`, sqrt, divider |
| SiLU path | 4 sigmoid lanes by default | Sequential LUT/interpolation engines |
| `llm_head_engine` | 4 int8 chunks per vocabulary row | Parameter RAM + `llm_math` |
| `llm_parameter_ram` | Model parameters, 24576×256 | One logical compute-read stream |
| `u_vectors` | Intermediate vectors | One logical read, masked write |
| `u_cache` | K/V cache | One logical read, masked write |

The parameter port is explicitly arbitrated between the linear engine, head engine, and parent controller. The vector and KV memories are also single logical read paths. Pasted text Pasted text

---

# 2. Real execution flow

For one token:

```text
Embedding
   ↓
for layer = 0..3
   RMSNorm
   ↓
   Q projection
   ↓
   K projection
   ↓
   V projection
   ↓
   RoPE(Q)
   ↓
   RoPE(K)
   ↓
   store current K/V
   ↓
   for head = 0..3
       stream Q·K[0..position]
       ↓
       find max score
       ↓
       serial exp/softmax/value pass
       ↓
       normalize 32 result lanes
   ↓
   O projection
   ↓
   residual add
   ↓
   RMSNorm
   ↓
   Gate projection
   ↓
   Up projection
   ↓
   SiLU
   ↓
   Gate × Up
   ↓
   Down projection
   ↓
   residual add
end

Final RMSNorm
   ↓
LM head: vocabulary 0..4095
   ↓
sampling / argmax
   ↓
next token
```

This is not merely inferred from the model structure: the graph FSM implements that sequence directly and waits for each graph operation's `op_done` before advancing. Pasted text

**Important:** the RTL already contains some good local pipelining. `ternary_dot32` is a four-stage pipeline with throughput one input per clock. Pasted text `llm_linear_engine` has a two-word credit window and overlaps parameter reads with its four SIMD chunks. Pasted text

It even prefetches the **next output row** during the scalar/store tail of the previous row. Pasted text

So the main problem is no longer simply "the RTL has no pipeline." The larger problem is:

> **The pipelines exist locally, but the complete inference graph is still transaction- and operation-serialized.**

---

# 3. Quantitative lower bounds and bottlenecks

There are no supplied captured `total_cycles`, graph-cycle counts, Fmax, or Quartus resource reports, although counters already exist in RTL. Therefore total cycles/token remains **NEEDS MEASUREMENT**. The RTL counters already count total cycles, parameter reads, KV accesses, math starts, divider starts and per-graph-state cycles. Pasted text

However, several useful architectural lower bounds can be derived.

### Transformer linear work

Per layer:

```text
Q     128 × 128 →  512 dot32 operations
K     128 × 128 →  512
V     128 × 128 →  512
O     128 × 128 →  512
Gate  384 × 128 → 1536
Up    384 × 128 → 1536
Down  128 × 384 → 1536
                     ----
                     6656 dot32/layer
```

Across four layers:

**26,624 `ternary_dot32` operations/token.**

Since the present ternary engine retires at most one 32-element dot request per cycle, **26,624 cycles/token is an absolute compute-side lower bound for these matrix operations alone**, before row setup, memory latency, scalar coefficient handling, writes, norm, attention or head.

The fixed 128/384 matrix dimensions are directly validated by `L_META`. Pasted text

### LM head

`llm_head_engine` performs four ordered int8 chunks per vocabulary row. Pasted text The parent iterates all the way to vocabulary row **4095** and does not move to the next row until scaling/sampling/select for the present row has finished. Pasted text

Thus even a hypothetically perfect streaming implementation with the **existing 256-bit single read stream** requires at least:

```text
4096 vocab × 4 words/logit
= 16,384 parameter-word issue cycles/token
```

The actual current value must be substantially above this floor because each row drains through memory latency, an 8-cycle sum-valid pipeline, scalar scale/round and selection before proceeding.

**Classification: COMPUTE + CONTROL/SERIALIZATION + MEMORY BANDWIDTH.**

This is likely one of the largest current cycles/token consumers.

### Attention normalization

Default `ATTN_DIV_LANES=4`.

There are 32 lanes → 8 batches/head. Each divider is a 64-iteration restoring divider. Pasted text Pasted text

Therefore the arithmetic alone is at least:

```text
8 batches × 64 divider iterations
= 512 divider iteration cycles/head

× 4 heads × 4 layers
= 8192 divider iteration cycles/token
```

plus ISSUE/ROUND/SIGN/CLAMP/NEXT_BATCH overhead.

**Classification: COMPUTE / SERIALIZATION.**

This is a major architectural target.

### RMSNorm

A normalization performs a 32-iteration integer square root followed by a 64-iteration divider. Pasted text

There are:

```text
ANORM × 4 layers
MNORM × 4 layers
FNORM × 1
= 9 normalizations/token
```

So sqrt+divide alone contributes a minimum of approximately:

```text
9 × (32 + 64)
= 864 iterative arithmetic cycles/token
```

before vector scans/scaling.

### SiLU

The FFN is 384 wide, i.e. 12 groups of 32 elements. With `SIGMOID_LANES=4`, each group of 32 requires eight sigmoid batches. The sigmoid itself is a multi-state READ0 → READ1 → SLOPE → MULTIPLY → ADD → ROUND unit. Pasted text

That means 96 sigmoid-group launches per layer, or 384/token. Again, the expensive part is not only arithmetic—it is serialized batching.

### Attention value pass

The Q·K score phase is relatively well streamed. After it finishes, however, the parent FSM processes each sequence element through:

```text
score read
→ exp preparation
→ interpolation
→ probability
→ KV read
→ weighted multiply
→ accumulate
→ next time
```

before proceeding to the next timestep. Pasted text

So this second attention pass scales much worse than the already-streamed QK engine.

**Classification: CONTROL/SERIALIZATION + MEMORY LATENCY.**

---

# 4. Hardware utilization

The performance limitation is currently **more "existing hardware is underutilized" than simply "not enough compute."**

The pattern is approximately:

```text
Linear projection
-----------------
ternary engine   BUSY
llm_math         mostly idle
divider/sqrt     idle
sigmoid          idle

Normalization
-------------
ternary engine   idle
llm_math         intermittently busy
sqrt/divider     busy

Attention
---------
ternary engine   idle
llm_math         busy
KV               busy

SiLU
----
ternary engine   idle
sigmoid          busy
llm_math         brief use

LM head
-------
ternary engine   idle
llm_math         busy
```

This follows directly from the graph-level operation sequencing and from the separate linear and `llm_math` engines. Pasted text

The current design therefore has useful opportunities for **producer-consumer overlap**, especially:

```text
Q produced → RoPE Q while tensor engine computes K
K produced → RoPE/cache while tensor engine computes V
V produced → cache independently

Gate tile produced → SiLU it while tensor engine computes Up
Gate/Up tile ready → multiply while later tiles are still computing

Attention result head N → projection preparation while later head works
```

The present graph requires complete tensor operations before entering those consumer phases.

---

# 5. Memory hierarchy today

Logical capacity is approximately:

| Storage | Geometry | Logical capacity |
|---|---:|---:|
| Parameter memory | 24,576 × 256 | **768 KiB** |
| KV cache | 4,096 × 768 | **384 KiB** |
| Vector workspace | 96 × 768 | **9 KiB** |
| Input cache | 12 × 768 | ~1.125 KiB |
| Attention score RAM | 128 × 32 | 512 B |
| Prompt + output tokens | 2 × 128 × 12 | 384 B |

So architecturally visible storage is roughly **1.14 MiB**, excluding implementation padding, lookup tables and ordinary registers.

The parameter memory has a five-cycle read pipeline at the present 24,576-row depth, and only one logical compute request stream. Pasted text

The vector/KV bank primitive likewise exposes one read request stream and a lane-masked write path; for up to 4096 rows the wrapper adds a multi-edge read pipeline. Pasted text

### Scaling implication

For the present 24-bit K/V representation:

```text
KV ≈ layers × context × 2 × hidden_dim × 24 bits
```

Current:

```text
4 × 128 × 2 × 128 × 24 bits
= 384 KiB
```

At the same model dimensions:

```text
context 1024 → ~3 MiB
context 4096 → ~12 MiB
```

Thus merely changing `CONTEXT=128` to a larger array is not a scalable architecture.

---

# 6. Model-specific restrictions

| Property | Current RTL | Classification | NPU v2 |
|---|---|---|---|
| Layers | exactly 4 (`layer_q != 3`) | MODEL-SPECIFIC | runtime |
| Hidden dimension | 128 | MODEL-SPECIFIC | runtime within max/tiled |
| Heads | 4 | MODEL-SPECIFIC | runtime |
| Head dimension | 32 | ARCH restriction | runtime/descriptor |
| FFN dimension | 384 | MODEL-SPECIFIC | runtime |
| Context | 128 / 7-bit position | MODEL-SPECIFIC | runtime length, compile-time max address width |
| Vocabulary | exactly 4096 scan | MODEL-SPECIFIC | runtime |
| Linear weights | ternary 2-bit | ARCH restriction | selectable supported format |
| LM-head weights | int8 | ARCH restriction | selectable precision |
| Activations | S24 fixed point | ARCH restriction | compile-time supported formats + runtime mode |
| RMSNorm | hardwired graph | MODEL-SPECIFIC | programmable operator |
| SiLU | hardwired | MODEL-SPECIFIC | programmable operator |
| RoPE | hardwired | MODEL-SPECIFIC | programmable/configurable |
| Full causal attention | hardwired | MODEL-SPECIFIC | programmable attention primitive |
| Sampling | greedy/Gumbel logic | MODEL-SPECIFIC | configurable output primitive |

The current 4-layer/context restriction can be seen both in `llm_pkg` and the graph's explicit layer/context termination logic. Pasted text Pasted text

---

# 7. Clock architecture decision

## A — current single clock

Best choice for the **current all-on-chip implementation**.

Advantages:

- zero CDC bubbles;
- no asynchronous FIFOs;
- simple scratchpad scheduling;
- all producer-consumer paths share cycle semantics;
- current RAM adapters already pipeline long physical paths.

## B — independent clocks for tensor/vector/attention engines

**Reject.**

It may raise the reported MHz of individual islands but does not remove:

```text
26,624 ternary-dot operations/token
4096-row LM-head scan
attention normalization division
operation-level serialization
```

It would introduce CDC latency and buffering exactly on paths we want to fuse.

## C — compute clock + external-memory/I/O clock

**Recommended for NPU v2.**

```text
Domain 0 — COMPUTE
    scheduler
    tensor engine
    vector/norm engine
    attention
    local buffers
    scratchpad
    on-chip KV

Domain 1 — MEMORY / I/O
    host
    DMA / load-store
    external DDR/HBM controller
    external-memory adapters

           async queues
Domain 0 <-----------> Domain 1
```

If NPU v2 is built initially with no external memory, both architectural domains may physically use the same clock.

So the conclusion is:

> **Use 2 architectural clock domains, but do not split the internal compute engines into separate clocks.**

This is about technology/interface isolation, not reducing cycles/token.

---

# 8. Memory abstraction for NPU v2

The good part of the present design should be preserved: it already has an SRAM abstraction and puts the Quartus-specific `altsyncram` implementation below that boundary. `pipelined_word_ram` is explicitly described as a replaceable SRAM adapter, while `quartus_word_ram` is the FPGA technology binding. Pasted text Pasted text

The boundary should evolve to:

```text
Engine local RF / FIFO
    fixed latency
          │
          ▼
Banked activation scratchpad
    req/ready + response-valid
          │
          ▼
Weight/KV tile buffers
    decoupled fill/drain
          │
          ▼
Load/Store + DMA
    burst descriptors
          │
          ▼
External-memory interface
          │
     +----+----+
     |         |
   FPGA      ASIC
 DDR/IP      memory fabric
```

Compute must never depend on M10K/M20K or future SRAM macro pin semantics.

For larger models:

- **register/local buffer:** current tile, accumulator, reused norm vector;
- **banked scratchpad:** activation working set, partial matrices, local KV window;
- **large/external memory:** model weights and eventually cold/large KV;
- **double-buffered weight buffers:** hide external-memory transfer behind compute.

---

# 9. Three architecture options

## Architecture A — Conservative

```text
                 SINGLE CLOCK

Host
 │
 ▼
existing llm_soc graph FSM
 │
 ├────────── Parameter RAM
 │
 ├── improved streaming linear engine
 ├── improved streaming LM head
 ├── llm_math
 ├── attention
 └── vector/KV RAM

Local changes:
- deeper row streaming
- more sigmoid lanes
- better attention normalization
- pipeline LM-head rows
```

Maximum RTL reuse. Keep graph FSM and current memories.

This should remove some large bubbles but leaves the fixed model graph and on-chip-capacity problem.

---

## Architecture B — Balanced — **recommended**

```text
                COMPUTE CLOCK
                      │
          +-----------▼------------+
          | Command scheduler      |
          | dependency scoreboard  |
          +---+----------+---------+
              |          |
       command FIFOs   command FIFOs
              |          |
       +------▼-----+ +--▼-------------+
       | Tensor     | | Vector/NORM    |
       | engine     | | /activation    |
       | 2×32 or 64 | +--+-------------+
       +------+-----+    |
              |          |
          local DBUFs    |
              |          |
       +------▼----------▼-------+
       | Banked activation       |
       | scratchpad              |
       +------+-----------+------+
              |           |
       +------▼---+   +---▼------+
       | K banks  |   | V banks  |
       +------+---+   +---+------+
              |           |
              +-----+-----+
                    ▼
           streaming attention
                    │
              score/top-k pipes

           weight tile buffers
                    ▲
                    │
            DMA / load-store
                    │
            asynchronous queues
                    │
                I/O CLOCK
                    │
            external memory
```

Key idea: still a specialized inference accelerator, **not a CPU**, but graph sequencing becomes descriptors/micro-ops and engines operate from queues.

---

## Architecture C — Aggressive / research-grade

```text
                   Command processor
                         │
                 distributed scheduler
                         │
       +-----------------+-----------------+
       |                 |                 |
  Compute tile 0    Compute tile 1    Attention tile
 tensor+vector       tensor+vector      QK/softmax/V
 local SRAM          local SRAM         local SRAM
       |                 |                 |
       +---------- banked fabric ----------+
                         │
               global scratchpad
                         │
                multi-channel DMA
                         │
              external model/KV memory
```

Add:

- multiple independent tensor tiles;
- distributed queues;
- tiled matrix execution;
- online/streaming softmax;
- local KV partitions;
- cross-tile dependency tokens;
- simple NoC/banked fabric only when multiple compute tiles justify it.

This has the strongest paper/research potential but is a substantially larger redesign.

---

# 10. Architecture comparison

| Metric | A — Conservative | B — Balanced | C — Aggressive |
|---|---|---|---|
| Cycles/token | ↓ moderate | **↓ large** | ↓ potentially very large |
| Throughput | moderate | **high** | very high |
| Fmax potential | similar/slightly ↑ | **high** through local boundaries | potentially high |
| Compute utilization | medium | **high** | very high |
| Area | low increase | medium | high |
| On-chip memory | current-like | configurable scratch/buffers | large distributed |
| Model scalability | poor-medium | **high** | very high |
| Model generality | poor | **high** | very high |
| FPGA suitability | excellent | **excellent** | medium |
| Future ASIC | medium | **excellent** | excellent |
| Implementation complexity | low | **medium** | very high |
| Research novelty | low | medium-high | **high** |
| Total cycle prediction | NEEDS MEASUREMENT | NEEDS MEASUREMENT | NEEDS MEASUREMENT |

**Architecture B is the best direction for this project.**

---

# 11. Priority table

| Priority | Architectural change | Current bottleneck | Expected cycles/token effect | Fmax | Cost | Scalability | Complexity | Confidence |
|---|---|---|---|---|---|---|---|---|
| **P0** | Fully stream LM-head rows; do not drain between vocabulary entries | CONTROL + head compute | Move toward **16,384-cycle theoretical head bandwidth floor** with present 256-bit port | +/0 | small-medium | high | medium | High |
| **P0** | Decouple global graph from engine execution using command FIFOs/local FSMs | CONTROL | Allows producer-consumer overlap | + | medium | very high | medium | High |
| **P0** | Banked scratchpad + separate K/V organization | PORTS/BANDWIDTH | Removes many read serialization bubbles | + | medium | high | medium | High |
| **P0** | Stream second attention pass | CONTROL/MEMORY | Multi-state/time → near one item/cycle pipeline after fill | + | medium | high | medium-high | High |
| **P0** | Replace 32 independent quotient operations with denominator-reuse architecture | COMPUTE | Current ≥512 divider iterations/head → one denominator operation + SIMD scaling/correction | + | medium | high | high if exact rounding required | High |
| **P0** | Decoupled weight-buffer/DMA architectural boundary | CAPACITY | Small model neutral; essential for larger models | 0/+ | buffers | **very high** | medium | High |
| **P1** | 2×32 or 64-lane ternary issue | COMPUTE | Linear lower bound **26,624 → ~13,312 dot issue cycles** if kept fed | maybe ↓/0 | medium | high | medium | High |
| **P1** | Tile-level Q/K/V and FFN overlap | UTILIZATION | substantial but workload-dependent | + | buffers | high | medium-high | High |
| **P1** | More sigmoid lanes / generic vector activation lane | SERIALIZATION | 8 batches/32 vals → 2 with 16 lanes or 1 with 32 | maybe ↓ | area | medium | low-medium | High |
| **P1** | Faster reciprocal-square-root normalization primitive | COMPUTE | removes recurring 32+64 iterative chain | + | medium | high | medium | Medium |
| **P2** | Multiple complete tensor engines | COMPUTE | useful only after memory/scheduling fixed | potentially ↓ | high | high | high | Medium |
| **P2** | Online softmax / FlashAttention-like decode dataflow | MEMORY/attention | could eliminate score storage/replay | + | medium | very high | high | Medium |
| **Reject** | Separate clocks for tensor/vector/norm blocks | TIMING only | does not fix cycles/token | uncertain | CDC overhead | low | high | High |
| **Reject now** | Full NoC | interconnect not yet dominant | negligible at current scale | uncertain | high | future only | very high | High |
| **Reject** | Simply enlarge current arrays | CAPACITY | no throughput benefit; eventually impossible | ↓ | huge | poor | low | High |
| **Reject** | Blindly widen SIMD before fixing data supply | UTILIZATION/BW | risks wider idle hardware | likely ↓ | high | medium | medium | High |

---

# 12. Recommended NPU v2

## What remains

Keep conceptually:

- `ternary_dot32`-style specialized low-bit arithmetic;
- pipelined general vector MAC/reduction;
- lookup-based activation primitives;
- portable SRAM adapter idea;
- saturate/RNE fixed-point primitives;
- host-visible model/configuration loading.

The existing arithmetic blocks already have useful pipelining; for example `llm_math` supports streaming input and separates product-valid from sum-valid. Pasted text

## What is redesigned

`llm_soc`'s graph FSM should stop directly micro-managing every RAM request, row, divider and vector operation.

Replace it with:

```text
model descriptor
      ↓
command sequencer
      ↓
dependency scheduler
      ↓
engine command queues
```

The current graph can initially be compiled into commands such as:

```text
NORM
MATVEC
ROPE
KV_WRITE
ATTENTION
VECTOR_MUL
VECTOR_ADD
ACTIVATE
LM_HEAD
```

No general-purpose ISA is required.

## What disappears

Eventually remove from the architectural level:

- 112-state global operation FSM;
- model-specific `G_Q/G_K/G_V/G_GATE/...` sequencing;
- hard-coded `layer_q != 3`;
- hard-coded vocabulary 4095;
- hard-coded vector addresses such as `60 + head_q`;
- fixed matrix metadata rules tied to 128/384 dimensions.

The current global FSM is useful as a migration reference, not as NPU v2's long-term architecture.

## What becomes compile-time parameterized

```text
TERNARY_LANES
VECTOR_LANES
number of tensor engines
number of scratchpad banks
local buffer depth
supported precision set
maximum address widths
number of normalization/divider lanes
```

## What becomes runtime configurable

```text
layers
hidden dimension
FFN dimension
head count
head dimension
context length
vocabulary
tensor strides
memory locations
precision per tensor
scales
attention configuration
```

## What becomes programmable

The **operator sequence and tensor dependencies**, but not arbitrary scalar instructions.

That is the correct balance between specialization and model generality.

---

# 13. Recommended NPU v2 compute organization

My preferred configuration is initially:

```text
1 × tensor/low-bit engine
    64 effective ternary lanes
    or two independent 32-lane issue pipelines

1 × vector engine
    32 lanes
    MAC / add / mul / reduce / norm helpers

1 × streaming attention controller
    uses vector MAC pipeline
    owns K/V scheduling and softmax pipeline

1 × streaming LM-head controller
    uses vector MAC pipeline
    keeps multiple vocabulary rows in flight

1 × banked activation scratchpad

separate K and V banks

2 × weight tile buffers (ping/pong)

1 × DMA/load-store engine
```

This does **not** duplicate every expensive arithmetic block. The intelligence is mainly in the **scheduling and buffering**, so the same compute has a much higher duty cycle.

---

# 14. Small → medium → larger model mapping

### Small model

```text
Weights       → on-chip parameter/scratchpad
KV            → on-chip
Activations   → scratchpad
DMA           → mostly idle
```

Essentially today's deployment, but running through the generic v2 architecture.

### Medium model

```text
Weights       → external memory
current layer → double-buffered weight SRAM
KV            → on-chip when possible
activations   → scratchpad
compute       ↔ DMA overlap
```

This is probably the most useful next practical target.

### Large model

```text
Weights       → external
KV            → mostly external / tiled
activations   → tiled scratchpad
operators     → tiled
tensor engine → consumes local tiles only
DMA           → continuously prefetches
```

At that scale the dominant metric changes from pure compute throughput to **bytes/token from external memory**.

---

# 15. Datapath/interconnect scaling

The current architecture relies on centralized 768-bit buses, centralized memory ownership and centralized operation decoding.

That works at 32 lanes but becomes unattractive with:

```text
64/128 lanes
multiple tensor engines
larger hidden dimensions
multiple simultaneous memory clients
```

Architecture B should therefore use:

```text
control:
small command FIFOs

data:
local engine buffers
        ↕
banked scratchpad

weights:
DMA → local weight buffers → tensor engine
```

Do **not** route every large operand through a global crossbar.

A NoC is unnecessary for one tensor engine + one vector engine. Introduce one only if Architecture C reaches several independent tiles.

---

# 16. Final NPU v2 diagram

```text
                         HOST
                           │
                 model / graph descriptors
                           │
                    I/O / MEM CLOCK
                           │
                +----------▼----------+
                | Load-Store / DMA    |
                | burst + prefetch    |
                +----+-----------+----+
                     |           |
              weight stream     KV spill/fill
                     |           |
              async queues / technology boundary
                     |           |
===================== CLOCK DOMAIN =====================
                  COMPUTE CLOCK
                     |
           +---------▼----------+
           | Command sequencer  |
           | + scoreboard       |
           +---+------+-----+---+
               |      |     |
       +-------+      |     +----------------+
       |              |                      |
+------▼-------+ +----▼---------+    +-------▼-------+
| Tensor       | | Vector/NORM  |    | Attention /   |
| engine       | | engine       |    | LM-head stream|
| 2×32 / 64    | | 32 lanes     |    | controllers   |
+------+-------+ +------+-------+    +-------+-------+
       |                |                    |
       +--------+-------+--------------------+
                |
      +---------▼----------------+
      | Banked activation        |
      | scratchpad               |
      +------+------+------------+
             |      |
          +--▼--+ +▼---+
          | K   | | V  |
          |bank | |bank|
          +-----+ +----+

       Weight buffer A / B
              ▲
              │
        Load-Store / DMA
              │
      technology-independent
         memory interface
              │
        +-----+------+
        |            |
      FPGA          ASIC
    BRAM/DDR      SRAM/DRAM
```

---

# 17. Migration path

```text
Current RTL
    │
    ▼
Phase 0 — expose architectural limits
    │
    ▼
Phase 1 — remove major serialization
    │
    ▼
Phase 2 — decouple execution + memory
    │
    ▼
NPU v2
```

| Phase | Structural changes | Main goal | Risk |
|---|---|---|---|
| **Phase 0** | Preserve RTL behavior; use existing performance counters to establish graph-state cycles, engine duty cycle and memory stalls | establish real cycles/token baseline | Low |
| **Phase 1** | Stream LM-head rows; stream attention value path; increase activation parallelism; improve normalization; retain graph FSM | remove largest local bubbles | Medium |
| **Phase 2** | Banked scratchpad, K/V separation, double buffers, command FIFOs, tile-level producer/consumer overlap | high engine utilization | Medium-high |
| **NPU v2** | Descriptor/micro-op execution, DMA/external-memory boundary, runtime dimensions, optional 64-lane tensor issue, 2-domain architecture | scalable/model-generic accelerator | Medium-high |

Metrics to record at every phase should be exactly the architectural ones already suggested by the design itself:

```text
cycles/token
cycles by graph state
ternary-engine utilization
llm_math utilization
parameter-port utilization
KV-port utilization
stall cycles
Fmax
logic / RAM resource usage
maximum model size
maximum context
```

---

# Bottom line

The current NPU is **not fundamentally bad because its arithmetic is too narrow**. Several arithmetic engines are already reasonably pipelined. The main architectural weakness is that a highly specialized global FSM turns them into mostly sequential appliances.

The order I would follow is therefore:

**LM-head streaming → attention/normalization serialization → engine-level decoupling → banked scratchpad + double buffering → runtime model descriptors → external-memory/DMA boundary → only then increase tensor parallelism.**

In particular, I would **not make multi-clock compute the next redesign**, and I would **not simply increase memory size**. The most appropriate target is **Architecture B**: a command-driven, locally queued, banked-memory accelerator with one high-throughput low-bit tensor engine, one vector engine, streaming attention/head control, and a technology-independent load/store boundary. That gives you a credible path from the current NanoFable implementation to larger contemporary models without throwing away the arithmetic RTL that already works.
