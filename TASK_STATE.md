# Phase 1A — continuous linear rows

- CURRENT remains Phase 1A in `docs/NPU_V2_EXECUTION.md`; do not start Phase 1B. Phase 1A RTL is on `main` (d53cdd9). Its timing and seven-group regression now have matching evidence; the remaining Phase 1A measurement gate is isolated parameter-stall counts.
- Verified RTL: `llm_linear_engine` streams ordered rows with two parameter-word credits and four reserved result slots; `llm_soc` pipelines the existing exact scalar/RNE/clamp/pack registers with row tags. The upper scaling partial is registered alongside the lower pair. Final completion drains engine results, scalar validity and accepted bank writes.
- Phase 1A source SHA256 (CRLF working-tree form): `llm_linear_engine.sv` = `fddea184893825d79758564a4f1ec03c7cb42ddd9d5a60fa633363727b2cd533`; `llm_soc.sv` = `ea6d6cea2a3bdb0cacc6fd0f5114198736adfdc2d6ec7dfac9908cf6f5fb062d`. All 41 RTL files on `main` match the timing manifest after CRLF normalization.
- Scoped evidence: `tests/full_rtl/evidence/phase1a_20261008/results.json`, `after_engine.log`, `after_soc.log`, `compile.log`, `portable_soc.log`. Scoped engine and SoC tests PASS; 1,920 numeric integration checks cover delayed consumption, saturation, six reset boundaries, and faults at rows 0/1/33 with older completed banks preserved. Compile: zero errors, nine checking warnings. Verilator behavioral-memory elaboration: zero errors with warnings; not synthesis/signoff.
- Seven-group regression: PASS for `main` under Xcelium 23.03 and Questa 2024.1 (baseline side of `tests/full_rtl/evidence/dead_states_20261024/results.json`). Graph: `clocks=570837 host_commands=196619`. The ModelSim operator failure in `phase1a_20261008/seven_groups_attempt.json` is the testbench `$deposit` fixture, not RTL; PR #3 replaces it with force/release.
- Timing: `docs/verification/timing/phase1a_linear_20261008/manifest.json` COMPLETE, source and configuration hashes verified. All four corners meet 100 MHz; minimum Fmax 101.28 MHz (slow 85 °C setup +0.126 ns); hold/recovery/removal/pulse nonnegative; zero unconstrained paths. 60,124 ALMs, 67,027 registers, 1,187 RAM blocks, zero DSPs. Map 23 warnings, fit 4, STA 0.
- Before/after actual Q/Down/Gate operator cycles: 2,227→701; 3,563→2,037; 6,579→1,981. Traffic is unchanged (129/385/385 parameter reads and 4/4/12 vector writes). Identical five-cycle-memory engine row initiation averages: 17→about 5 clocks for 128 inputs, 27→about 15 for 384 inputs. Two-word parameter credits still expose response gaps; isolated parameter-stall counts remain unmeasured.
- Required module guides and live verification status are synchronized. Diagram follow-up required is recorded in both module guides; diagrams were not edited.

## Dead op-state removal (PR #3, not merged)

- Branch `claude/remove-dead-op-states` removes the 25 unreachable op states from `llm_soc.sv` (`OP_COUNT` 112→87, indices renumbered, ten return labels removed). `tb_operators` checks the scalar clamp path at linear stage 4 and drops the attention-only variants.
- Evidence: candidate side of `tests/full_rtl/evidence/dead_states_20261024/results.json`. 28/28 runs (seven groups × baseline/candidate × Xcelium/Questa) `rc=0`, zero errors. Six groups' PASS markers match baseline exactly, including graph clocks. Operators PASS with checks 6,611→5,843, clamp cases 516→260 and scalar reset cases 6→3 (removed attention variants); other counts unchanged. Xcelium 8 `*W,NODNTW` per run on both sides; Questa none.
- Not run for this RTL: Quartus synthesis/fit/STA, portable elaboration, pretrained application. The 101.28 MHz result applies to the Phase 1A source only.

## Next action

- After PR #3 is reviewed and merged, run full-top timing on the merged RTL with a fresh tag (`tools/timing/run.ps1` with `quartus/llm_soc`) before claiming its Fmax/resources.
- Measure isolated parameter-stall counts to close the Phase 1A gates, then advance `docs/NPU_V2_EXECUTION.md`. The `overflow_out` scope decision is still with the user.

## Separate pretrained application context

- Earlier context-128 reference export completed (prompt 4 + continuation 124); a matching completed application PASS has not been established. Previous inputs: `Once upon a time`, NewTokens=124, MinNew=124, Temperature=0, Seed=7; hardware gate skipped. Prior wrapper/status path: `tests/full_rtl/build/full128_20261007_2022/`; application log: `tests/full_rtl/build/application.log`.
- Its continuation/provenance is separate from Phase 1A. Source hashes for any result produced from the pre-change compiled design must identify that baseline; do not promote it to current RTL PASS.
