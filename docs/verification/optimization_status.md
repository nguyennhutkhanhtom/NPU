# Current verification and implementation status

> **Category: CURRENT.** Single owner of live checkpoint results. Updated 2026-10-08 (Asia/Saigon); manifests/logs remain primary evidence.

## At a glance

Phase 1A RTL now streams consecutive linear rows with two parameter-word credits, four reserved row-result slots, and tagged validity through the existing scalar/pack registers. Architectural completion drains results, scalar validity and accepted writes. [Matching scoped evidence](../../tests/full_rtl/evidence/phase1a_20261008/results.json) records exact engine rows, backpressure, fault/drain/cancel/reset, and 1,920 SRAM/scaling/RNE/saturation/packing checks. ModelSim compilation has zero errors and nine checking warnings; the scoped SoC fixture retains the same 32 force-select warnings as the preserved baseline.

| Existing numeric fixture | Before cycles | Phase 1A cycles | Parameter reads / vector writes (unchanged) |
|---|---:|---:|---|
| Q: 128 inputs, 128 rows | 2,227 | 701 | 129 / 4 |
| Down: 384 inputs, 128 rows | 3,563 | 2,037 | 385 / 4 |
| Gate: 128 inputs, 384 rows | 6,579 | 1,981 | 385 / 12 |

The identical five-cycle-memory engine fixture changes average row initiation from 17 to approximately 5 clocks for 128 inputs, and 27 to approximately 15 for 384 inputs. Dot issue utilization over the scoped Q/Down/Gate operations rises from 23.0/43.1/23.3% to 73.0/75.4/77.5%; parameter request utilization rises from 5.8/10.8/5.9% to 18.4/18.9/19.4%. Startup/drain counts are retained in the profile logs; they are not isolated parameter-stall counts. The two-word credit window still exposes parameter-response gaps. Before/after logs are preserved in the same evidence directory.

Five groups in the [seven-group attempt](../../tests/full_rtl/evidence/phase1a_20261008/seven_groups_attempt.json) pass (memory, math, RAM, protocol, selection). The operator group encounters the same `$deposit` scalar fixture failure as unchanged baseline RTL under ModelSim; graph regression remains pending. Questa is unavailable while another session holds its single-session license. Vendor-free Verilator elaboration of `llm_soc` with behavioral memory completes with zero errors and diagnostic warnings; this is not synthesis or ASIC signoff.

Full-top synthesis/fit/STA is running under `phase1a_linear_20261008`; see [continuation state](../../TASK_STATE.md). New Fmax/resource results and the complete regression are pending, so `NPU_V2_EXECUTION.md` remains at CURRENT Phase 1A. The prior 95.61 MHz timing source hashes match the preserved pre-change snapshot, not the modified RTL.

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
