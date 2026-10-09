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

- Phase 1A — continuous linear-row execution
- Phase 1B — LM-head row streaming

CURRENT:

- Phase 1C — attention value-pass streaming

NEXT:

- Phase 2 — descriptor-driven serial execution

### Phase 1A closure

Phase 1A is CLOSED. Frozen-source scoped engine/SoC tests, the operator and graph groups, and full-top synthesis/fit/STA/extraction pass. The other five regression groups retain matching-source PASS evidence. Questa operators pass 6,611 checks and graph passes at 570,837 compute clocks with exact token, causal and memory-traffic assertions. The ModelSim `$deposit` fixture failure reproduces on unchanged baseline and does not reproduce in Questa. No Phase 1B implementation was performed.

| Existing linear fixture | Before cycles | After cycles | Reduction |
|---|---:|---:|---:|
| Q: 128 inputs, 128 rows | 2,227 | 701 | 68.52% |
| Down: 384 inputs, 128 rows | 3,563 | 2,037 | 42.83% |
| Gate: 128 inputs, 384 rows | 6,579 | 1,981 | 69.89% |

Average engine row initiation changes from 17 to approximately 5 clocks for 128 inputs and 27 to approximately 15 for 384 inputs. Q/Down/Gate dot-issue utilization changes from 23.0/43.1/23.3% to 73.0/75.4/77.5%; parameter-request utilization changes from 5.8/10.8/5.9% to 18.4/18.9/19.4%. Parameter and vector traffic is unchanged. Isolated parameter-stall counts were not measured; the two-word credit window still exposes parameter-response gaps.

Worst fitted Fmax improves from 95.61 to **101.28 MHz** (+5.93%), with all four corners passing the 100 MHz target and no unconstrained paths. Worst setup is +0.126 ns at slow 1.1 V, 85°C. Resources: 60,124 ALMs (+404), 67,027 registers (+82), 1,187 RAM blocks (+1), 9,516,700 memory bits (+156), zero DSPs. This is FPGA evidence, not ASIC signoff.

Evidence: [scoped results and metrics](../tests/full_rtl/evidence/phase1a_20261008/metrics.json), [operator/graph completion](../tests/full_rtl/evidence/phase1a_20261008/closing_groups.json), [timing manifest](verification/timing/phase1a_linear_20261008/manifest.json). Current RTL/configuration and result-log hashes were verified before closure; no rerun or RTL/configuration change was required.

## Measurement gates

### Phase 1B closure

Remote Xcelium scoped tests and all nine groups PASS (jobs 64347/64351, black, mandatory X11). Current/frozen inputs and all 37 full-regression report hashes were verified. The existing operator fixture checks every row's dot, packed scale, exact score and PRNG order, delayed result consumption, six reset/cancellation boundaries including final-row retirement, and complete drain. Selection adds tagged-path excluded-token, minimum-score, stable-tie and saturated-tie checks. Graph tokens and traffic remain exact; compute clocks fall from 570,837 to 280,602.

| Head fixture | Before | Phase 1B |
|---|---:|---:|
| Sampled cycles/pass, temperature 166 | 121,886 | 16,949 (-86.09%) |
| Greedy cycles/pass, context 1 and 128 | 113,694 | 16,949 (-85.09%) |
| Parameter-read utilization, sampled / greedy | 13.86% / 14.86% | 99.69% |
| SIMD dot-issue utilization, sampled / greedy | 13.44% / 14.41% | 96.67% |
| Average row initiation, sampled / greedy | 29.75 / 27.75 clocks (derived from baseline schedule) | 4.125 clocks (measured) |
| Maximum rows in flight | 1 | 7; 10 with forced backpressure (8 engine reservations plus epilogue) |

Each pass still reads 16,384 weight words and 512 packed-scale words and issues 16,384 SIMD dots. Scale words occupy 512 shared-port clocks; zero steady-state credit or result-consumption stalls were measured. A forced 24-clock result pause gives 8 credit-stall and 21 result-stall clocks, adding 8 pass clocks without changing output. Scaling/selection runs concurrently with weights instead of blocking each next row. The remaining head throughput limit is the single parameter-read port, including its scale traffic.

Phase 1B is DONE. Baseline/after Genus jobs 64352/64350 completed synthesis, mapping and optimization with RAM-blackbox integrity PASS (352 instances, three intended empty module types), zero error diagnostics and no unexpected unresolved references. Frozen inputs, current Phase 1B runtime inputs, all 12 report hashes per run, matching library hashes and unchanged 10 ns SDC were verified. Warning categories match the baseline; the additional unused-register warning removes the retired `chunk_q`. The generic-area warning precedes mapping; comparisons below use mapped `area.rpt`.

| Genus mapped logic, slow library at 0.9 V / 125 C | Before | Phase 1B |
|---|---:|---:|
| Cell count | 236,846 | 238,919 (+2,073; +0.88%) |
| Cell area, library units | 812,007.590 | 818,368.756 (+0.78%) |
| Reported worst setup slack at 100 MHz | +5 ps | 0 ps, MET at report precision |
| Reported critical data path | 9,933 ps | 9,938 ps |

Critical paths remain in the shared `llm_math` product-to-first-reduction stage. The head remains parameter-bandwidth limited; synthesis timing has effectively no reported margin. RAM black boxes exclude SRAM area/timing, and these Genus results do not establish physical timing closure or a new FPGA Fmax.

Evidence: [measured comparison](../tests/full_rtl/evidence/phase1b_20261008/metrics.json), [full remote results](../tests/full_rtl/evidence/phase1b_20261008/full/extracted/phase1b_full_20261008/results.json), [synthesis review](../tests/full_rtl/evidence/phase1b_20261008/synthesis_review.json), [baseline synthesis](../tests/full_rtl/evidence/phase1b_20261008/syn_baseline/extracted/phase1b_baseline_syn_final/results.json), [Phase 1B synthesis](../tests/full_rtl/evidence/phase1b_20261008/syn_after/extracted/phase1b_after_syn_20261008/results.json). Library SHA256: `dec616b7b53aa5166eac9660ba83561a4057ee3b7e62f59f3d4bebad495ffe10`. Phase 1C is CURRENT; implementation and scoped results are recorded below.

- Phase 1A must measure linear-phase cycles, ternary-dot issue utilization, parameter stalls/utilization, row initiation interval, and Fmax.
- Phase 1B must measure head cycles/token, rows in flight, weight/scale bandwidth, SIMD utilization, and selection/epilogue stalls.
- Phase 1C must measure attention cycles versus context, KV bandwidth/stalls, `llm_math` utilization, and normalization share.

### Phase 1C verification — closure pending

`llm_soc` pipelines exact exp interpolation into eight reserved V-response slots and retires tagged SIMD lane products in timestep order. Q×K, shared arithmetic and exact normalization RTL are unchanged. Xcelium scoped job 64357 on black with mandatory X11 passes math, operators and host cancellation with zero simulator diagnostics. All 60 current/frozen runtime inputs and 13 report hashes match. Operators pass 113,131 checks, including independent per-timestep probabilities, signed products, running denominators/accumulators, exact outputs, contexts 1/2/4/7/8/9/127/128, score bubbles, forced SIMD backpressure and 20 reset/cancellation boundaries through final-product/reduction drain. Existing Phase 1A/1B operator checks retain PASS.

| Attention fixture (four heads) | Phase 1B baseline | Phase 1C scoped |
|---|---:|---:|
| Context 4, total clocks | 2,762 | 2,482 (-10.14%) |
| Context 128, total clocks | 15,162 | 3,474 (-77.09%) |
| Context 128, value-loop clocks | 12,288 (derived: 24 × 128 × 4) | 600 (measured, includes drain) |
| Timestep initiation interval | 24 clocks (derived schedule) | 1 clock (measured) |
| Maximum timesteps in flight | 1 | 15; 17 with forced backpressure |

Context-128 value-pass KV-request/product utilization is 512/600 = 85.33%, with zero steady-state credit/operand stalls. A 24-clock forced SIMD pause fills all eight reserved response slots, produces 22 credit-stall and 24 operand-stall clocks, and adds exactly 24 clocks without changing output. Seven score-bubble clocks add exactly seven clocks. KV traffic remains 1,024 reads (K plus V), with four query reads and four output writes. Normalization remains 2,248 clocks for four heads and occupies 64.71% of the improved context-128 attention pass.

Full Xcelium job 64359 passes all nine groups with zero simulator diagnostics; all 60 current/frozen runtime inputs and 37 report hashes match. Exact graph tokens/causal behavior/traffic are preserved. Graph clocks decrease 280,602 → 278,330 (-0.81%); attention-phase clocks decrease 41,808 → 39,536 (-5.43%). The fixture generates three tokens after a two-token prompt: average clocks per generated token, including prefill, decrease 93,534 → 92,776.67. These short-context graph gains differ from the isolated context-128 attention improvement.

Evidence: [scoped results](../tests/full_rtl/evidence/phase1c_20261009/scoped3/extracted/phase1c_scoped3_20261009/results.json), [full regression](../tests/full_rtl/evidence/phase1c_20261009/full/extracted/phase1c_full_20261009/results.json), [profiles](../tests/full_rtl/evidence/phase1c_20261009/metrics.json). Baseline Phase 1B regression/synthesis hashes and the unchanged 10 ns SDC were reverified. Matching Genus job 64360 on black with mandatory X11 completed all stages; all 60 input/12 report hashes and 352 intended SRAM black boxes are verified, with zero errors or unexpected unresolved modules. Mapped logic area is 870,961.790 (+6.43%), cell count 249,803 and reported 10 ns setup slack +16 ps; the 9,744 ps critical data path runs from SIMD product to lane accumulator. Library/SDC hashes match Phase 1B. [Synthesis review](../tests/full_rtl/evidence/phase1c_20261009/syn_checked/review.json). SRAM area/timing and physical closure are excluded; overall trade-off acceptance remains pending. See [continuation](../tests/full_rtl/build/scratchpad/phase1c_20261009/handoff.md). Phase 1C is not DONE; Phase 2 has not started. Genus timing is separate from physical timing closure.
- Additional scratchpad ports/banks wait for measured simultaneous-client stalls; DMA buffer depth waits for measured compute time, transfer latency, and bytes/token.
- A second clock waits for a real asynchronous interface requirement.
- Wider tensor, activation, normalization, or multi-tile compute waits for evidence that memory and scheduling can keep it busy.
