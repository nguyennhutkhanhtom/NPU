# Current verification and implementation status

> **Category: CURRENT.** Single owner of live checkpoint results. Updated 2026-10-25 (Asia/Saigon); manifests/logs remain primary evidence.

## At a glance

The current RTL is the [Phase 1B](#phase-1b-lm-head-row-streaming) LM-head stream. It passes the seven groups, both stream fixtures and SpyGlass lint with zero errors under two simulators. Run directly on the server, outside the gated flow, the pretrained application matches all 96 tokens under Xcelium in 9,884,334 clocks (19,958,382 before). Questa gives the same result. Full-top timing meets 100 MHz at all four corners (minimum Fmax 101.53 MHz). The gated `run_application.ps1` flow and portable elaboration have not been run for this RTL.

The previous RTL (`main` eb4274f) meets 100 MHz at all four corners (minimum Fmax 100.74 MHz) and passes the [gated pretrained application](#gated-pretrained-application): 96/96 tokens equal the reference.

## Phase 1B: LM-head row streaming

`llm_head_engine` now streams all 4,096 vocabulary rows from one start. It sends one ordered read stream: each eight-row group's packed scale word, then four int8 weight words per row. At most eight reads are outstanding, and two scale slots alternate by group. Retired rows carry their S39 sum and U24 scale into a six-stage epilogue in `llm_soc`. Stages 0–3 reuse the linear scalar multiplier and RNE24. Stage 3 also forms the Gumbel noise product and advances the PRNG once per row. Stage 4 adds the RNE8 noise, and stage 5 saturates, applies eligibility and keeps stable lowest-ID ties. Zero temperature gives a zero noise product, so the old greedy bypass is no longer needed. Nine per-row states are removed (`OP_COUNT` 87 → 78). Numeric behavior, PRNG order and host protocol are unchanged.

Measured on the `tb_llm_operators` head fixture (4,096 rows, real parameter SRAM with its five-edge response). [Evidence](../../tests/full_rtl/evidence/phase1b_20261025/results.json):

| Head pass | Before (eb4274f) | Phase 1B |
|---|---:|---:|
| Cycles, temperature 166 | 121,886 | 16,948 (7.19×) |
| Cycles, temperature 0 | 113,694 | 16,948 (6.71×) |
| Parameter reads (16,384 weight + 512 scale) | 16,896 | 16,896 |
| Parameter-port use | 13.9% / 14.9% | 99.7% |
| SIMD issue use (16,384 issues) | 13.4% / 14.4% | 96.7% |
| Rows in flight, first weight request to selection | 1 | max 7, mean 6.05 |
| Parameter-port idle cycles during the stream | — | 0 |
| Epilogue stalls | — | 0 |

The head is now bound by the single parameter read port: 16,896 reads take 16,896 of 16,948 cycles. Each row needs 4.125 words (1,056 bits), 528 KiB per token. At one 256-bit word per clock this is 3.2 GB/s at 100 MHz. The new engine fixture `tb_llm_head_stream` checks every row's S39 sum and U24 scale against a wide-integer reference through the real streaming `llm_math`. At latency 5 it takes 16,913 cycles with at most five rows in the engine. At latency 1 it takes 16,909. At latency 40 the eight read credits bound the stream (86,611 cycles, 69,663 credit stalls) and every row is still exact. It also covers cancel at six phases with full drain, and reset at four phases, each followed by an exact pass.

The synthetic graph takes 280,599 clocks (570,837 before, −50.8%) with the same 196,619 host commands. Its three greedy head passes save exactly 3 × 96,746 cycles.

In the [regression](../../tests/full_rtl/evidence/phase1b_20261025/results.json), the seven groups, `tb_llm_linear_stream` and `tb_llm_head_stream` pass under Xcelium 23.03 and Questa 2024.1 with zero errors. The same seven groups and linear fixture also pass on the baseline in the same session. Xcelium reports 8 `*W,NODNTW` per run on both sides; Questa reports none. `tb_llm_selection` and the operator scalar check now drive the epilogue stage validity instead of the removed states, and they keep the same checks.

SpyGlass X-2025.06 `lint/lint_rtl` on portable `llm_soc` (`USE_QUARTUS_MEMORY=0`, `mthresh` 65536 so no module is black-boxed) reports 0 errors. Warnings drop from 106 to 86, and no message is new against the baseline. The removed 20 are double-assignment warnings of the deleted per-row states. Verilator 5.041 `--lint-only -Wall` reports 0 errors and 79 warnings on both sides. Its single new warning flags the unused scale-slot bits [31:24], by design.

The pretrained NanoFable export of 2026-10-07 (same prompt and settings as below, byte-identical files) passes `application_tb.sv` under Xcelium with the clamp census bound ([evidence](../../tests/full_rtl/evidence/phase1b_20261025/results.json)). All 96 tokens equal the reference: `FULL_RTL_APPLICATION_PASS tokens=96 clocks=9884334 host_commands=196722 overflow=0`. This is 50.5% fewer clocks, and the saving equals 96 × (121,886 − 16,948). The census sees 393,216 head scores (96 × 4,096), none saturated, and the activation and exp-underflow counts are unchanged. Questa 2024.1 gives the same line with zero warnings. These runs are outside `run_application.ps1`; that gated flow has not been run for this RTL.

Full-top timing [phase1b_head_stream_20261025](timing/phase1b_head_stream_20261025/manifest.json) covers this RTL. All 41 RTL files and the QPF/QSF/SDC match the candidate tree after CRLF normalization. All four corners meet 100 MHz: minimum Fmax 101.53 MHz, worst setup +0.151 ns at slow 0 °C (`pc_debug[2]~reg0` → `pc_debug[2]`); slow 85 °C is +0.158 ns on `vector_q[378]` → `input_cache_q[11][378]`. Hold, recovery, removal and pulse slack are nonnegative at every corner, TNS is zero and no path is unconstrained. Fitted: 59,900 ALMs, 67,270 registers, 1,187 RAM blocks, 9,516,700 memory bits, zero DSPs (previous RTL: 59,751 ALMs, 66,775 registers). Map 24 warnings, fit 4, STA 0. Every Phase 1B measurement gate now has evidence, so `NPU_V2_EXECUTION.md` records Phase 1B as DONE.

Diagram follow-up required: the draw.io RTL hierarchy and `docs/diagrams/hierarchy_manifest.json` still show the old head engine ports (`vocabulary_i`, `done_o`, start from `H_SCALE`).

Phase 1A RTL now streams consecutive linear rows with two parameter-word credits, four reserved row-result slots, and tagged validity through the existing scalar/pack registers. Architectural completion drains results, scalar validity and accepted writes. [Matching scoped evidence](../../tests/full_rtl/evidence/phase1a_20261008/results.json) records exact engine rows, backpressure, fault/drain/cancel/reset, and 1,920 SRAM/scaling/RNE/saturation/packing checks. ModelSim compilation has zero errors and nine checking warnings; the scoped SoC fixture retains the same 32 force-select warnings as the preserved baseline.

| Existing numeric fixture | Before cycles | Phase 1A cycles | Parameter reads / vector writes (unchanged) |
|---|---:|---:|---|
| Q: 128 inputs, 128 rows | 2,227 | 701 | 129 / 4 |
| Down: 384 inputs, 128 rows | 3,563 | 2,037 | 385 / 4 |
| Gate: 128 inputs, 384 rows | 6,579 | 1,981 | 385 / 12 |

The identical five-cycle-memory engine fixture changes average row initiation from 17 to approximately 5 clocks for 128 inputs, and 27 to approximately 15 for 384 inputs. Dot issue utilization over the scoped Q/Down/Gate operations rises from 23.0/43.1/23.3% to 73.0/75.4/77.5%; parameter request utilization rises from 5.8/10.8/5.9% to 18.4/18.9/19.4%. Before/after logs are preserved in the same evidence directory. Isolated parameter stalls are now counted in that fixture ([evidence](../../tests/full_rtl/evidence/fault_drain_stalls_20261024/results.json)), whose five-cycle response matches `llm_parameter_ram` in `llm_soc`. Every parameter word after the first two waits one cycle: 126 of 653 cycles for 128×128 and 382 of 1,933 for the 384-word matrices (19.3%/19.8%), plus six startup cycles. Result-slot stalls are zero without backpressure. The cause is the two-word credit window, which covers four issue cycles per word against the five-cycle response.

The [seven-group regression](../../tests/full_rtl/evidence/dead_states_20261024/results.json) (baseline side, `main` d53cdd9) passes all seven groups under Xcelium 23.03 and Questa 2024.1 with zero errors. The synthetic graph takes 570,837 compute clocks (840,053 before Phase 1A) with 196,619 host commands. The earlier ModelSim [attempt](../../tests/full_rtl/evidence/phase1a_20261008/seven_groups_attempt.json) stopped in the operator group on the testbench `$deposit` scalar fixture, not on RTL. Vendor-free Verilator elaboration of `llm_soc` with behavioral memory completes with zero errors and diagnostic warnings; this is not synthesis or ASIC signoff.

Full-top timing [phase1a_linear_20261008](timing/phase1a_linear_20261008/manifest.json) completed with verified source and configuration hashes; all 41 RTL files of `main` d53cdd9 match it after CRLF normalization. All four corners meet 100 MHz: minimum Fmax 101.28 MHz, worst setup +0.126 ns at slow 85 °C, hold/recovery/removal/pulse nonnegative, zero unconstrained paths. Fitted: 60,124 ALMs, 67,027 registers, 1,187 RAM blocks, 9,516,700 memory bits, zero DSPs. Map 23 warnings, fit 4, STA 0. Every Phase 1A measurement gate now has evidence, and the current RTL below has its own passing timing, so `NPU_V2_EXECUTION.md` records Phase 1A as DONE; see [continuation state](../../TASK_STATE.md).

## PR #3: dead op-state removal and restored fault-drain fix

PR #3 removes the 25 unreachable op states from `llm_soc` (`OP_COUNT` 112 → 87). In the [dead-state evidence](../../tests/full_rtl/evidence/dead_states_20261024/results.json), 28/28 runs (seven groups × baseline/candidate × two simulators) finish with `rc=0` and zero errors. Memory, math, RAM, protocol, selection and graph markers are identical to baseline, including graph clocks. Operators pass with 6,611 → 5,843 checks, 516 → 260 clamp cases and 6 → 3 scalar reset cases, because the attention-only variants of the removed `A_*` path are dropped.

PR #3 also restores two changes that were merged into `main` on 2026-10-22 and 2026-10-24 (PR #1 Vietnamese docs fix, PR #2 fault-drain fix) and were lost when `main` was reset to d53cdd9. With PR #2, `G_DONE` returns to `G_IDLE` only when `op` is back in `O_IDLE`. Without it, a relaunch during a fault drain consumes the drained operation's completion and skips the embedding. In the [final evidence](../../tests/full_rtl/evidence/fault_drain_stalls_20261024/results.json), 16/16 candidate runs (seven groups plus `tb_llm_linear_stream`, two simulators) pass with zero errors. Six groups repeat the dead-state candidate markers. Protocol adds `fault_drain_relaunch=checked` (180 transactions, 16 token cases). The same protocol test on `main` RTL stops with `Relaunch consumed a stale fault completion` under both simulators. Xcelium reports 8 `*W,NODNTW` per run; Questa reports none.

Full-top timing [dead_states_fault_drain_20261024](timing/dead_states_fault_drain_20261024/manifest.json) covers this RTL. All 41 RTL files and the QPF/QSF/SDC match `main` eb4274f. All four corners meet 100 MHz: minimum Fmax 100.74 MHz, worst setup +0.073 ns at slow 85 °C (`vector_q[733]` → `input_cache_q[1][733]`; the Phase 1A fit was limited by a parameter-RAM read into `math_b_q` instead). Hold, recovery, removal and pulse slack are nonnegative at every corner, TNS is zero and no path is unconstrained. Fitted: 59,751 ALMs, 66,775 registers, 1,187 RAM blocks, 9,516,700 memory bits, zero DSPs (Phase 1A: 60,124 ALMs, 67,027 registers). Map 24 warnings, fit 4, STA 0. Portable elaboration has not been run for this RTL.

## Gated pretrained application

The current RTL (`main` cb1ffc4, RTL unchanged since eb4274f) passes the full gated flow on the local Questa Altera Starter 2025.2.

- **Seven groups:** `run_units.ps1 -Questa` passes all seven ([evidence](../../tests/full_rtl/evidence/units_pr3_20261024/results.json)). Compile and simulation logs have zero errors and zero warnings. The markers equal the server runs, including graph `clocks=570837 host_commands=196619`.
- **Gate:** `check_gate.py` with the [dead_states_fault_drain_20261024](timing/dead_states_fault_drain_20261024/manifest.json) manifest prints `FULL_RTL_APPLICATION_GATE_PASS: Fmax=100.74 MHz`.
- **Application:** `run_application.ps1` passes ([evidence](../../tests/full_rtl/evidence/application_gated_20261025/application_results.json)).
  - Settings: prompt "Once upon a time, Lily found a tiny kitten." (11 IDs), 96 new tokens, temperature 166, seed 7, `MinNew` 64.
  - All 96 RTL tokens equal the integer reference: `FULL_RTL_APPLICATION_PASS tokens=96 clocks=19958382 host_commands=196722 overflow=0`, with `hardware_gate=PASS`. Compile and simulation report zero errors and warnings.
  - The exported parameter, prompt, expected and config files are byte-identical to the 2026-10-07 export used in the direct runs below.
  - Simulation took 12 h 38 min of wall time.
- **Text quality:** still `NOT_ASSESSED` in the result file. The [decoded continuation](../../tests/full_rtl/evidence/application_gated_20261025/generated_text.md) is fluent TinyStories-style English with weak coherence between sentences. Token matching does not measure text quality.

## Pretrained checkpoint run and saturation census

On the merged RTL, the pretrained NanoFable export of 2026-10-07 (same prompt and settings) passes `application_tb.sv` directly under Xcelium and Questa. All 96 tokens equal the reference, in 19,958,382 clocks with `overflow_out=0` ([evidence](../../tests/full_rtl/evidence/clamp_census_20261024/results.json)). These direct runs are outside `run_application.ps1`; the gated run above repeats them.

The same runs bind `tests/full_rtl/clamp_monitor.sv`, which counts saturation at every clamp site. None of the 1,449,216 activation clamp samples saturates: linear, embedding, RMSNorm, RoPE, residual, SiLU, GMUL and attention output. Only the designed exp underflow fires (557 of 90,736 attention probabilities set to zero). The monitor reproduces the deliberate saturation fixtures of `tb_llm_operators`, and the synthetic graph saturates nowhere. `overflow_out` therefore keeps its linear-only scope, now documented in `docs/design/host_interface.md`.

## Prior verified checkpoint (before Phase 1A)

| Claim | Latest applicable evidence | Result / scope |
|---|---|---|
| Seven-group regression | [arch_final_20261007](../../tests/full_rtl/evidence/arch_final_20261007/results.json) | PASS for preserved pre-Phase-1A RTL; seven synthetic groups |
| Synthetic graph | Same regression | 840,053 compute clocks; two prompt IDs, three generated IDs, 16 layer executions; numeric/causal/traffic checks retained |
| Portable elaboration | [portable_arch_20261007](portable_arch_20261007/results.json) | ELABORATION_PASS for pre-Phase-1A RTL; zero errors/warnings; vendor-free `run 0`, not ASIC signoff |
| Synthesis / fit | [arch_fulltop2_20261007](timing/arch_fulltop2_20261007/manifest.json) | Both completed with zero errors; 22 map warnings, four fit warnings |
| All-corner timing at 100 MHz | Same timing manifest | FAIL; minimum Fmax 95.61 MHz; worst setup −0.459 ns / TNS −3.266 ns at slow 85°C |
| Other timing checks | Same timing manifest | Hold/recovery/removal/pulse nonnegative at all four corners; zero unconstrained paths/clocks/ports |
| Resources | Same fitted checkpoint | 59,720 ALMs; 66,945 registers; 1,186 RAM blocks; 9,516,544 memory bits; zero DSPs |
| Host cancellation | No fresh dedicated archive established here | Earlier `opt_host1` is historical; do not claim its hashes match changed RTL |
| Pretrained application | No matching completed application result found | Current timing gate fails; no current application PASS established |

Raw RTL hashes were compared directly for the prior regression, portable and timing evidence against the pre-change snapshot. All three QPF/QSF/SDC hashes match the timing manifest under its declared LF normalization. Timing manifest recorded 2026-10-07T11:07:17Z. STA completed with zero errors and one warning. Separate stage completion from timing closure and application validation.

## Previous implementation checkpoint

P0 greedy selection bypasses noise/sample states at zero temperature while retaining exact score selection and one PRNG advance per vocabulary row. P1 starts at most one next linear row during the current scalar/store tail, retaining ordered accumulator/fault completion and drain/reset behavior. See [implementation rationale](../../review/architecture_optimization_20261007.md).

Measured synthetic graph clocks decreased from the 2026-10-06 baseline 1,066,965 to 840,053 (21.27%). Linear phases decreased from 611,168 to 408,832; head from 365,661 to 341,085. Traffic remains 77,756 parameter reads, 1,828 vector reads, 1,564 vector writes, 320 KV reads and 128 KV writes.

The first fit, [arch_fulltop1_20261007](timing/arch_fulltop1_20261007/manifest.json), reached 101.53 MHz with setup +0.151 ns but failed reset recovery (−0.045 ns). Restoring the baseline reset-register site corrected recovery in the second fit but setup now fails on `vector_q[398]~DUPLICATE` → `input_cache_q[7][398]`. The implementation decision remains REVISE pending review; no further RTL or placement change was made by the documentation refactor.

## Historical comparisons

[Throughput review v3](../reviews/rtl_change_review_v3.md) records the earlier `opt_final4`/`opt_fulltop7` snapshot. [NanoFable timing snapshot](nanofable_max_20261006.md) records that earlier source/configuration, not current timing or application results. Preserved fail/canceled/intermediate evidence must not be promoted to current PASS.

## Verification and application gate

[Verification procedure and gate](README.md#pretrained-application-gate) owns the requirements. [Language demo](../demos/language.md) owns execution commands. Keep the 100 MHz constraints and report measured Fmax even when timing fails. Quartus evidence is FPGA implementation evidence only.
