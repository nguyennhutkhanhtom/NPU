# Current verification and implementation status

> **Category: CURRENT.** Single owner of live checkpoint results. Updated 2026-10-24 (Asia/Saigon); manifests/logs remain primary evidence.

## At a glance

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

## Pretrained checkpoint run and saturation census

On the merged RTL, the pretrained NanoFable export of 2026-10-07 (prompt "Once upon a time, Lily found a tiny kitten.", 96 new tokens, temperature 166, seed 7) passes `application_tb.sv` directly under Xcelium and Questa. All 96 tokens equal the reference, in 19,958,382 clocks with `overflow_out=0` ([evidence](../../tests/full_rtl/evidence/clamp_census_20261024/results.json)). This run is outside `run_application.ps1`, so it is not the gated pretrained-application claim. Timing for this RTL now passes; the gate also needs a passing local seven-group `run_units.ps1` result in `tests/full_rtl/unit_results.json`, which has not been run for this RTL.

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
