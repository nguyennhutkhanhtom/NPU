# Phase 1A — continuous linear rows

- CURRENT remains Phase 1A in `docs/NPU_V2_EXECUTION.md`; do not start Phase 1B. Every Phase 1A measurement gate now has evidence. Advance the milestone only after the PR #3 RTL has its own timing result.
- Verified RTL: `llm_linear_engine` streams ordered rows with two parameter-word credits and four reserved result slots; `llm_soc` pipelines the existing exact scalar/RNE/clamp/pack registers with row tags. Final completion drains engine results, scalar validity and accepted bank writes.
- Phase 1A source SHA256 (CRLF working-tree form): `llm_linear_engine.sv` = `fddea184893825d79758564a4f1ec03c7cb42ddd9d5a60fa633363727b2cd533`; `llm_soc.sv` = `ea6d6cea2a3bdb0cacc6fd0f5114198736adfdc2d6ec7dfac9908cf6f5fb062d`. All 41 RTL files of `main` d53cdd9 match the timing manifest after CRLF normalization.
- Phase 1A scoped evidence: `tests/full_rtl/evidence/phase1a_20261008/`. Engine/SoC tests PASS; 1,920 numeric integration checks; Verilator behavioral-memory elaboration zero errors (not synthesis/signoff).
- Phase 1A timing: `docs/verification/timing/phase1a_linear_20261008/manifest.json` COMPLETE. All four corners meet 100 MHz; minimum Fmax 101.28 MHz (slow 85 °C setup +0.126 ns); 60,124 ALMs, 67,027 registers, 1,187 RAM blocks, zero DSPs.
- Phase 1A cycles: Q/Down/Gate operators 2,227→701, 3,563→2,037, 6,579→1,981; traffic unchanged. Parameter stalls (`tests/full_rtl/evidence/fault_drain_stalls_20261024/results.json`, five-cycle response as in `llm_soc`): one stall per parameter word after the first two. That is 126 of 653 cycles for 128×128 and 382 of 1,933 for 384-word matrices (19.3%/19.8%), plus six startup cycles; result-slot stalls zero. The cause is the two-word credit window.

## PR #3 (branch `claude/remove-dead-op-states`)

- Removes the 25 unreachable op states (`OP_COUNT` 112→87). It restores two changes lost when `main` was rewritten to d53cdd9 during the Claude co-author cleanup: PR #1 Vietnamese docs fix and the PR #2 fault-drain fix. With the PR #2 fix, `G_DONE` waits for `op == O_IDLE`. `tb_linear_stream` gains parameter-stall counters.
- Evidence: `tests/full_rtl/evidence/dead_states_20261024/results.json` (28/28 base/candidate) and `tests/full_rtl/evidence/fault_drain_stalls_20261024/results.json`. In the second, 16/16 runs of candidate 9e73944 pass with zero errors: seven groups plus `tb_llm_linear_stream`, under Xcelium 23.03 and Questa 2024.1. Graph `clocks=570837 host_commands=196619`; protocol adds `fault_drain_relaunch=checked`. The same protocol test on `main` RTL stops with `Relaunch consumed a stale fault completion` in both simulators. Xcelium 8 `*W,NODNTW` per run; Questa none.
- Not run for this RTL: portable elaboration, pretrained application.

## Running job: full-top timing for the PR #3 RTL

- Tag `dead_states_fault_drain_20261024`. Started 2026-10-24T09:13:24Z from worktree `push-len-giup-236d23` at 9e73944 with `tools/timing/run.ps1 -Project quartus/llm_soc -QuartusBin C:\altera_lite\25.1std\quartus\bin64` under `pwsh`. Driver PID 62540.
- Stage logs: `docs/verification/timing/dead_states_fault_drain_20261024/{map,fit,sta,extract}.log`. Earlier full-top runs took about 62 min (fit about 52 min).
- Process check: `Get-Process -Id 62540,(Get-Process quartus_* -ErrorAction SilentlyContinue).Id -ErrorAction SilentlyContinue`.
- Progress: `Get-ChildItem docs/verification/timing/dead_states_fault_drain_20261024/*.log | Select-Object Name,Length,LastWriteTime`.
- Completion: `manifest.json` appears in that directory, and the driver prints `TIMING_EVIDENCE_RECORDED` and `TIMING_100MHZ_PASS|FAIL`. Do not edit `.sv/.svh/.mem` or `quartus/llm_soc.{qpf,qsf,sdc}` in that worktree until then.
- On completion: read `manifest.json` once, confirm its RTL hashes equal the PR #3 sources, and record Fmax/resources in `docs/verification/optimization_status.md`. If timing is met, advance `docs/NPU_V2_EXECUTION.md` past Phase 1A.

## Next action

- Record the timing result above. The `overflow_out` scope (currently linear outputs only, as in every earlier RTL) is still the user's decision.

## Separate pretrained application context

- Earlier context-128 reference export completed (prompt 4 + continuation 124); a matching completed application PASS has not been established. Previous inputs: `Once upon a time`, NewTokens=124, MinNew=124, Temperature=0, Seed=7; hardware gate skipped. Prior wrapper/status path: `tests/full_rtl/build/full128_20261007_2022/`; application log: `tests/full_rtl/build/application.log`.
- Its continuation/provenance is separate from Phase 1A. Source hashes for any result produced from the pre-change compiled design must identify that baseline; do not promote it to current RTL PASS.
