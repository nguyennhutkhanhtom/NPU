# NPU v2 execution contract

This is the compact source of truth for staged NPU v2 implementation. Work only on the current phase; do not pull later-phase architecture into an earlier change.

## Frozen architecture decisions

### What stays

- Specialized ternary dot-product hardware and exact fixed-point behavior.
- The shared 32-lane `llm_math` multiply/reduction pipeline and lookup-based activation primitives.
- Explicit round/saturate behavior and ordered fault, cancellation, and reset semantics.
- The portable SRAM-adapter boundary with technology-specific memory leaves.
- Host-loaded parameters/configuration and bounded accelerator-style commands.

### What changes

- Linear and LM-head paths become continuous row pipelines, including scaling, rounding, packing, selection, and completion.
- The attention value pass becomes a streaming score-exp, V-fetch, weighted-accumulate path with explicit response alignment.
- Fixed NanoFable constants become descriptors for dimensions, tensor locations/strides, token semantics, numeric modes, and attention parameters.
- Descriptor execution is serial first; concurrency follows only after operand, response, completion, and writeback ownership are explicit.
- Larger models use bounded weight/KV tile buffers and a backpressured DMA/load-store boundary with a bytes-per-token budget.

### Explicitly deferred or rejected

- Independent clocks for tensor, vector, norm, attention, or local SRAM.
- Mandatory two-clock operation when the external interface is synchronous; CDC exists only at a genuinely asynchronous external interface.
- A NoC, full distributed scoreboard, or multiple complete compute tiles.
- Premature 64-lane ternary widening, large activation replication, or approximate reciprocal normalization.
- Enlarging the current arrays as the model-scaling strategy.

## Migration phases

- **Phase 1A — linear row streaming:** continuously pipeline memory issue, ternary dots, scalar scaling, rounding, packing, and writeback while preserving exact accumulation and ordered drain/fault behavior.
- **Phase 1B — LM-head row streaming:** keep multiple vocabulary rows in flight through weights, packed scales, sampling, selection, stable ties, and ordered PRNG advancement.
- **Phase 1C — attention value-pass streaming:** pipeline score read, exponent interpolation, V fetch, weighted multiplication, and accumulation with explicit tags/validity; retain exact normalization.
- **Phase 2 — remove model-specific contracts / descriptor-driven serial execution:** describe dimensions, addresses/strides, scales, token rules, RoPE, and attention scaling; add tiled accumulation; execute descriptors serially.
- **Phase 3 — selected compute overlap and resource ownership:** add only dependency-safe Q/K/V, RoPE/cache, FFN, and writeback overlap after concurrent clients have independent state, response routing, completion, and writeback ownership.
- **Phase 4 — DMA/external-memory scaling:** add backpressured load/store commands, bounded ping-pong weight/KV buffers, separate prefill/decode schedules, and CDC queues only when an external interface is asynchronous.
- **Phase 5 — compute widening only if measurements justify it:** widen ternary issue, divider/normalization lanes, activation lanes, or compute-tile count only after bandwidth and utilization evidence identifies the resource as limiting.

## Global implementation constraints

- Preserve functional and numerical behavior unless the active phase explicitly changes the numeric contract.
- Use one compute clock for scheduler, engines, local buffers, scratchpad, and KV.
- Place CDC only at a genuinely asynchronous external memory or I/O boundary.
- Do not introduce a NoC, full distributed scoreboard, or premature 64-lane issue.
- Preserve the portable SRAM abstraction and its documented latency/collision contract.
- Modify only RTL and synchronized module documentation relevant to the active phase.
- Preserve host-visible protocol, ordering, faults, cancellation, and reset behavior.
- Complete and measure each phase before starting the next major phase.

## Key active RTL anchors

| File | Module | States/signals/blocks to inspect |
|---|---|---|
| `Verilog Source code/llm_soc.sv` | `llm_soc` | graph FSM; `L_ROW_START/L_ROW_WAIT/L_COEFF/L_STORE`; `H_SCALE/H_STREAM_WAIT/H_COEFF/H_SELECT`; `A_EXP_READ`–`A_ACC`; parameter mux; `input_cache_q`; `math_start`; `op_done`; `g_perf` |
| `Verilog Source code/llm_linear_engine.sv` | `llm_linear_engine` | `IDLE/RUN/DRAIN`; request/response credits; two-word FIFO; `operand_capture`; accumulator; fault/drain completion |
| `Verilog Source code/ternary_dot32.sv` | `ternary_dot32` | `valid_i/valid_o`; four-stage pipeline; reserved-code fault |
| `Verilog Source code/llm_head_engine.sv` | `llm_head_engine` | row request/response/sum counters; `parameter_req_o`; `math_issue_o`; `done_o` |
| `Verilog Source code/llm_attention_engine.sv` | `llm_attention_engine` | KV request stream; score memory; maximum reduction; score scaling |
| `Verilog Source code/llm_attention_normalize.sv` | `llm_attention_normalize` | batches; divider lanes; quotient/remainder RNE; sign/clamp |
| `Verilog Source code/llm_math.sv` | `llm_math` | `in_ready`; `product_valid`; `sum_valid`; `done`; shared ownership |
| `Verilog Source code/llm_parameter_ram.sv` | `llm_parameter_ram` | single compute-read stream; accepted request; response-valid latency |
| `Verilog Source code/llm_bank_ram.sv`, `pipelined_word_ram.sv` | memory adapters | single logical read; masked write; `rd_valid`; `wr_busy`; portable tiled request/response boundary |

## Progress

DONE:

- none

CURRENT:

- Phase 1A — continuous linear-row execution

NEXT:

- Phase 1B — LM-head streaming

## Measurement gates

- Phase 1A must measure linear-phase cycles, ternary-dot issue utilization, parameter stalls/utilization, row initiation interval, and Fmax.
- Phase 1B must measure head cycles/token, rows in flight, weight/scale bandwidth, SIMD utilization, and selection/epilogue stalls.
- Phase 1C must measure attention cycles versus context, KV bandwidth/stalls, `llm_math` utilization, and normalization share.
- Additional scratchpad ports/banks wait for measured simultaneous-client stalls; DMA buffer depth waits for measured compute time, transfer latency, and bytes/token.
- A second clock waits for a real asynchronous interface requirement.
- Wider tensor, activation, normalization, or multi-tile compute waits for evidence that memory and scheduling can keep it busy.
