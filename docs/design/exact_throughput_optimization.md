# Exact throughput architecture

The fixed graph remains four transformer layers, 128 channels, four 32-channel attention heads, 384 feed-forward channels, 4,096 vocabulary entries and context at most 128. Host loading, graph phase IDs, fixed-point rounding, saturation, overflow/error policy, sampling exclusions, stable lowest-ID ties and PRNG order retain their prior contracts. This change targets cycles and avoidable SRAM transactions. FPGA EDA measurements do not establish ASIC PPA or signoff.

## Resource ownership

`llm_soc` owns the graph, matrix metadata, normalized operand cache, coefficient scaling, vector writes, attention probability/value pass and sampling. Three bounded engines own their regular streaming passes:

| Module | Ownership | Shared resources |
|---|---|---|
| `llm_linear_engine` | One exact ternary row, two-word parameter prefetch credits, response drain and reserved-code fault | Parameter SRAM and the parent's immutable operand cache |
| `llm_head_engine` | Four ordered int8 chunks for one vocabulary row, request/response counters and S39 accumulation | Parameter SRAM, cached final hidden vector and SIMD reduction |
| `llm_attention_engine` | Causal Q/K requests, streamed score rounding/scaling, score storage and maximum | KV SRAM, held query and SIMD reduction |
| `llm_attention_normalize` | Exact RNE division, sign restoration and S24 clamp in bounded batches | Lane zero shares the RMSNorm divider; three additional dividers provide four-way attention normalization |
| `ternary_dot32` | S25 sign/zero terms and a balanced registered S30 reduction | Dedicated portable add/subtract logic |

Each regular pass drains its responses before the parent changes resource ownership. Parameter SRAM requests have one owner at a time. Graph regression checks this invariant and the two-word linear credit limit. Only `quartus_word_ram` explicitly instantiates vendor memory IP.

The divider and sigmoid replication parameters are elaboration geometry and must
be powers of two dividing 32: 1, 2, 4, 8, 16 or 32. This verification uses the
approved default of four for both. Physical timing/utilization evidence applies
to the production defaults, with performance counters and opcode debug encoding
disabled. Other elaboration configurations require their own matched evidence.

## Cache and stores

One 12 x 768-bit register cache serves mutually exclusive linear/head operations. Linear preloading is mandatory for Q, O, Gate and Down. Reuse is restricted to Q/K/V and Gate/Up with matching source, geometry and family. Source writes, reset, launch, faults and head entry invalidate linear cache ownership. Head reloads the four final-normalized input rows for every invocation. The cache has 9,216 payload bits; no separate head cache is added.

The head holds one 256-bit scale word for eight vocabulary rows. Each coefficient occupies 24 bits in a 32-bit slot. Row order and every PRNG update are retained. RoPE K reuses Q's table only when valid for the same position; it still reads its own K vector. Loading norm gains into the shared table storage invalidates the RoPE tag.

Linear scalars accumulate in the existing `write_vector_q`. No SRAM transaction occurs for a partial row. Lane 31 is captured before the following full-mask transaction, and operation completion waits for memory write drain. Four reset probes cover prefetched memory, in-flight dot data, coefficient processing and the final lane before flush. Fresh execution must reproduce all independent S128 expected results.

## SIMD response protocol

`llm_math` retains the legacy default interface and completion timing. `STREAMING=1` accepts `start && in_ready` on every clock, including while prior transactions occupy the pipeline. Reset deasserts ready and cancels validity. For an acceptance at E0, products are valid at E3, reductions at E8 and legacy `done` at E9. Separate `product_valid` and `sum_valid` signals identify their different pipeline stages. Streaming consumers use the reduction validity; one-outstanding-request operators retain their existing completion protocol. No wide product delay queue is added merely to align unrelated response channels.

The arithmetic regression retains 503 legacy transactions and adds sustained/sparse streaming scoreboards, ternary reserved-code/S24_MIN checks and exact normalizer tests against S128 arithmetic. Normalization captures quotient and rounding metadata, then separates rounding, sign restoration and clamp into registered stages. Four sigmoid lanes process groups of four without changing the interpolation or RNE calculations.

## Expected transaction geometry

| Per transformer layer or head invocation | Baseline | Optimized |
|---|---:|---:|
| Linear vector reads / layer | 6,656 | 24 |
| Linear vector write transactions / layer | 1,408 | 44 |
| RoPE parameter reads / layer | 4 | 2 |
| Head vector reads / invocation | 16,384 | 4 |
| Head scale reads / invocation | 4,096 | 512 |

Full synthetic graph expectations for two prompt tokens, three generated tokens and sixteen layer executions are 77,756 parameter reads, 1,828 vector reads, 1,564 vector write transactions, 320 KV reads and 128 KV writes. These are transaction counts, not energy or throughput estimates. Tests must match both numeric outputs and these counts. Actual cycle, area and timing measurements belong to immutable checkpoint manifests and the implementation report.

## Active and legacy source isolation

`isqrt_u64` and `sram_word_tile` are standalone source files. The full-top Quartus file list no longer compiles legacy `norm`, `banked_word_ram` or `sram_256_wrapper`. The legacy modules remain available to their independent regression runner. Existing paths are retained to preserve working callers and historical source references. Reserved operator IDs are retained where earlier tests inject scalar clamp/rounding stages; they are not new graph operations.

Approximate reciprocal normalization is outside this exact implementation. No timing exceptions, relaxed numeric tests or board deployment requirements are introduced. Pretrained application execution still requires exact-current seven-group PASS and full-top post-fit >=100 MHz at all four corners, all setup/hold/recovery/removal/pulse slacks nonnegative, TNS=0 and no unconstrained paths.
