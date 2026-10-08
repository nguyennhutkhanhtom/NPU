# Phase 1A — continuous linear rows

- CURRENT remains Phase 1A in `docs/NPU_V2_EXECUTION.md`; do not implement Phase 1B. Full-top timing and the operator gate now pass; the graph regression is running. RTL/configuration remain frozen.
- Verified RTL: `llm_linear_engine` streams ordered rows with two parameter-word credits and four reserved result slots; `llm_soc` pipelines the existing exact scalar/RNE/clamp/pack registers with row tags. The upper scaling partial is registered alongside the lower pair. Final completion drains engine results, scalar validity and accepted bank writes.
- Frozen source SHA256: `llm_linear_engine.sv` = `fddea184893825d79758564a4f1ec03c7cb42ddd9d5a60fa633363727b2cd533`; `llm_soc.sv` = `ea6d6cea2a3bdb0cacc6fd0f5114198736adfdc2d6ec7dfac9908cf6f5fb062d`. Do not edit RTL/configuration while the timing job measures it.
- Matching evidence: `tests/full_rtl/evidence/phase1a_20261008/results.json`, `after_engine.log`, `after_soc.log`, `compile.log`, `portable_soc.log`. Scoped engine and SoC tests PASS; 1,920 numeric integration checks cover delayed consumption, saturation, six reset boundaries, and faults at rows 0/1/33 with older completed banks preserved. Compile: zero errors, nine checking warnings. SoC fixture: 32 existing ModelSim force-select warnings, also present in baseline. Verilator behavioral-memory elaboration: zero errors with warnings; not synthesis/signoff.
- Existing seven-group attempt: five groups PASS (memory, math, RAM, protocol, selection), preserved in `tests/full_rtl/evidence/phase1a_20261008/seven_groups_attempt.json`. The `$deposit` failure reproduces on unchanged baseline under ModelSim; the full unchanged operator fixture now passes in Questa (29 operators, 6,611 checks, 128 scalar cases, 516 clamp cases, zero errors/warnings). This distinguishes the simulator fixture issue from a Phase 1A regression. Current operator log: `tests/full_rtl/build/tb_llm_operators.log`. Graph is the only remaining group.
- Before/after actual Q/Down/Gate operator cycles: 2,227→701; 3,563→2,037; 6,579→1,981. Traffic is unchanged (129/385/385 parameter reads and 4/4/12 vector writes). Identical five-cycle-memory engine row initiation averages: 17→about 5 clocks for 128 inputs, 27→about 15 for 384 inputs. Logs and pre-change source hashes are preserved in the same evidence directory. Two-word parameter credits still expose response gaps; isolated parameter-stall counts remain unmeasured.
- Baseline timing: `docs/verification/timing/arch_fulltop2_20261007/manifest.json`, minimum Fmax 95.61 MHz. All 41 RTL/LUT hashes match the preserved pre-change snapshot. Do not apply that Fmax to Phase 1A.
- Required module guides and live verification status are synchronized. Diagram follow-up required is recorded in both module guides; diagrams were not edited.

## Verified full-top timing

- Status: Done

- `tests/full_rtl/build/phase1a_timing_status.json` inspected once on continuation: COMPLETE. Manifest: `docs/verification/timing/phase1a_linear_20261008/manifest.json`. Do not relaunch timing.
- Map/fit/STA and extraction succeeded: zero errors; warnings 23/4/0 for map/fit/STA; `TIMING_EXTRACTION_PASS:` verified. All 41 current RTL/LUT hashes, all three normalized QPF/QSF/SDC hashes, commands/snapshot hashes and archived report hashes match. Configuration also matches the 95.61 MHz baseline. The scoped engine/SoC test input hashes still match their PASS evidence.
- 100 MHz timing PASS: worst Fmax 101.28 MHz (+5.67 MHz, about +5.93%). Slow 1.1 V 85°C: 101.28 MHz, setup +0.126 ns; slow 0°C: 101.53 MHz, setup +0.151 ns. Fast 85°C/0°C: 152.35/167.06 MHz. Hold/recovery/removal/pulse slack is positive at all four corners; all unconstrained counts are zero.
- Fitted resources versus baseline: 60,124 ALMs (+404); 67,027 registers (+82); 1,187 RAM blocks (+1); 9,516,700 memory bits (+156); zero DSPs and 186 pins (unchanged). FPGA evidence only.

## Active missing-regression handoff

- Status: Done

- Only missing groups were launched: `tests/full_rtl/run_units.ps1 -SimBin C:/altera_lite/25.1std/questa_fse/win64 -Questa -MemoryModelManifest tests/full_rtl/build/application_memory_model/manifest.json -TimingManifest docs/verification/timing/phase1a_linear_20261008/manifest.json -OnlyTop tb_llm_operators,tb_llm_graph -WorkLibraryName phase1a_close -EvidenceTag phase1a_close_20261008`.
- Started 2026-10-08 09:29:44 Asia/Saigon; tool session `24630`. No simulator was active before launch. The single initial status check found operators PASS and the remaining graph stage running. Runner PID `21376`, `vsim.exe` PID `38108`, `vsimk.exe` PID `12124`. Do not terminate another user's simulator, poll repeatedly, or relaunch this job.
- Compile completed with zero errors/warnings (`tests/full_rtl/build/compile.log`). Operator completion marker: `LLM_OPERATORS_PASS operators=29 checks=6611`; no new Phase 1A errors observed.
- Current graph log: `tests/full_rtl/build/tb_llm_graph.log`; console: `tests/full_rtl/build/tb_llm_graph.log.console`. Runner status/result: `tests/full_rtl/unit_results.json`; initial source/test snapshot: `tests/full_rtl/build/phase1a_close_20261008_modelsim_start.json`.
- One bounded process check: `Get-Process -Id 21376,38108,12124 -ErrorAction SilentlyContinue | Select-Object Id,ProcessName,CPU`.
- One bounded progress/log-tail command: `Get-Content -LiteralPath tests/full_rtl/build/tb_llm_graph.log -Tail 12`.
- Completion: `LLM_GRAPH_PASS` in the graph log, followed by `SELECTED_GROUPS_PASS` in `tests/full_rtl/unit_results.json`, with actual RAM binding integrity verified for graph. Expected outputs include graph traffic/cycles, both group markers/hashes, and `tests/full_rtl/build/phase1a_close_20261008_tb_llm_graph_design_units.json`.
- Continue after job completion: inspect final status once and verify the frozen RTL/test hashes and graph assertions. Preserve results. Only when graph passes and all Phase 1A gates hold, update `docs/NPU_V2_EXECUTION.md`: Phase 1A DONE, final linear metrics/Fmax recorded, Phase 1B CURRENT. Do not implement Phase 1B. If a failure is confirmed, distinguish fixture/environment failure from a Phase 1A regression before considering RTL changes.

## Separate pretrained application context

- Earlier context-128 reference export completed (prompt 4 + continuation 124); a matching completed application PASS has not been established. Previous inputs: `Once upon a time`, NewTokens=124, MinNew=124, Temperature=0, Seed=7; hardware gate skipped. Prior wrapper/status path: `tests/full_rtl/build/full128_20261007_2022/`; application log: `tests/full_rtl/build/application.log`.
- Its continuation/provenance is separate from Phase 1A. Source hashes for any result produced from the pre-change compiled design must identify that baseline; do not promote it to current RTL PASS.

## Server password authentication flow

- Status: Done

## Server synthesis flow

- Status: In progress
