# Phase 1B DONE

- `docs/NPU_V2_EXECUTION.md`: Phase 1A DONE; Phase 1B DONE; no CURRENT phase.
- Candidate RTL: worktree branch `claude/gated-application` (uncommitted), on top of `main` eb4274f. Changed RTL: `llm_head_engine.sv` and `llm_soc.sv` only.
  - `llm_head_engine` streams all 4,096 vocabulary rows from one start: per eight-row group one packed scale word, then four int8 weight words per row; at most eight reads outstanding; two scale slots; ordered S39 row results with their U24 scale; cancel drains accepted reads and SIMD sums.
  - `llm_soc` starts the engine on the last `H_PRELOAD` chunk and waits in `H_STREAM_WAIT`. A six-stage epilogue (`head_pipe_valid_q`) reuses scalar stages 0–3, then noise/PRNG (stage 3), sampled score (4) and selection (5). Nine per-row states are removed (`OP_COUNT` 78). `O_FINISH` also waits for `head_busy` and the head stages.

## Evidence for the candidate

- Simulation: `tests/full_rtl/evidence/phase1b_20261025/results.json`. 18/18 candidate runs pass (seven groups, `tb_llm_linear_stream`, new `tb_llm_head_stream`) under Xcelium 23.03 and Questa 2024.1 on the server; the baseline passes its 16 runs in the same session. Graph `clocks=280599 host_commands=196619` (baseline 570,837).
- Head pass (`tb_llm_operators`): 121,886 → 16,948 cycles at T=166, 113,694 → 16,948 at T=0. Parameter port 99.7% busy, SIMD 96.7%, rows in flight max 7 / mean 6.05, zero port idle and zero epilogue stalls.
- Lint: SpyGlass X-2025.06 `lint/lint_rtl` 0 errors, 0 new messages (106 → 86 warnings). Verilator 5.041 0 errors; one intended new UNUSEDSIGNAL (scale-slot bits [31:24]).
- Pretrained application, run directly on the server outside the gate: Xcelium PASS, 96/96 tokens, `clocks=9884334 host_commands=196722 overflow=0` (19,958,382 before); clamp census `head_score` 393,216 samples, 0 saturated. Questa 2024.1 PASS with identical clocks, 0 warnings.
- Not run for this RTL: gated `run_application.ps1`, portable elaboration.

## Timing

- Full-top timing `docs/verification/timing/phase1b_head_stream_20261025/manifest.json`: `TIMING_100MHZ_PASS`, minimum Fmax 101.53 MHz, setup +0.151 ns, all corners nonnegative, 41 RTL + QPF/QSF/SDC hashes match. 59,900 ALMs, 67,270 registers, 1,187 RAM blocks, zero DSPs.

## Local tool notes

- The documented Python runtime `C:/Users/khanh/.cache/codex-runtimes/.../python.exe` no longer exists. The packages in `tests/language_demo/packages` are cp312, so pass `-Python` with the uv Python 3.12 (`uv python find 3.12`).
- Checkpoint assets live in the main checkout (`D:/2151097_Nguyen Nhut Khanh/tests/language_demo/{upstream,packages}`). Worktrees need a copy of `upstream` and a junction to `packages`.
- Simulation speed: the seven groups take about 39 min locally and about 2 min on the server (12 parallel jobs); the 96-token application took about 12.5 h locally on the previous RTL.
- Server lint: SpyGlass needs `set_option mthresh 65536`, otherwise `llm_soc`, `llm_math` and `sram_word_tile` are black-boxed. Runner: `tests/full_rtl/evidence/phase1b_20261025/runners/lint_one.sh`.

## Next action

- Optional: gated `run_application.ps1` with the Phase 1B manifest; diagram follow-up for the head engine ports. Phase 1C only on request.
