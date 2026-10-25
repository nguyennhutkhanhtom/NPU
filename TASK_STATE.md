# Phase 1A done — Phase 1B not started

- `docs/NPU_V2_EXECUTION.md`: Phase 1A DONE, CURRENT Phase 1B (not started). Do not start Phase 1B without an explicit request.
- Verified RTL: `main` eb4274f. It is the Phase 1A linear streaming RTL plus PR #3: 25 dead op states removed (`OP_COUNT` 87), and `G_DONE` waits for `op == O_IDLE` after a fault. `llm_linear_engine` streams ordered rows with two parameter-word credits and four reserved result slots; final completion drains engine results, scalar validity and accepted bank writes.

## Evidence for the current RTL

- Simulation: `tests/full_rtl/evidence/fault_drain_stalls_20261024/results.json`. 16/16 runs pass: seven groups plus `tb_llm_linear_stream`, under Xcelium 23.03 and Questa 2024.1 on the server. Graph `clocks=570837 host_commands=196619`. The protocol run records `fault_drain_relaunch=checked`.
- Timing: `docs/verification/timing/dead_states_fault_drain_20261024/manifest.json`.
  - All 41 RTL files and QPF/QSF/SDC match eb4274f.
  - All four corners meet 100 MHz: minimum Fmax 100.74 MHz, worst setup +0.073 ns at slow 85 °C. Every other check is nonnegative and no path is unconstrained.
  - Resources: 59,751 ALMs, 66,775 registers, 1,187 RAM blocks, zero DSPs.
- Phase 1A measurements:
  - Q/Down/Gate cycles 2,227→701, 3,563→2,037 and 6,579→1,981.
  - Parameter stalls are one per word after the first two (19.3%/19.8%), caused by the two-word credit window. Result-slot stalls are zero.
  - Evidence: `tests/full_rtl/evidence/phase1a_20261008/` and `fault_drain_stalls_20261024`.
- Gated pretrained application: PASS on local Questa Altera Starter 2025.2.
  - Seven groups: `tests/full_rtl/evidence/units_pr3_20261024/` (also `tests/full_rtl/unit_results.json`).
  - `check_gate.py` prints `FULL_RTL_APPLICATION_GATE_PASS: Fmax=100.74 MHz`.
  - Application: `tests/full_rtl/evidence/application_gated_20261025/`. 96/96 tokens equal the reference, `clocks=19958382 host_commands=196722 overflow=0`, `hardware_gate=PASS`. Text quality is not assessed.
- Pretrained runs outside the gate: `tests/full_rtl/evidence/clamp_census_20261024/results.json`. Same tokens under Xcelium and Questa 2024.1, and no activation clamp saturates. `overflow_out` stays linear-only; this is documented in `docs/design/host_interface.md`.
- Not run for this RTL: portable elaboration.

## Local tool notes

- The documented Python runtime `C:/Users/khanh/.cache/codex-runtimes/.../python.exe` no longer exists. The packages in `tests/language_demo/packages` are cp312, so pass `-Python` with the uv Python 3.12 (`uv python find 3.12`).
- Checkpoint assets live in the main checkout (`D:/2151097_Nguyen Nhut Khanh/tests/language_demo/{upstream,packages}`). Worktrees need a copy of `upstream` and a junction to `packages`.
- Simulation speed: the seven groups take about 39 min; the 96-token application takes about 12.5 h.

## Next action

- Phase 1A has no open item. Phase 1B (LM-head streaming) starts only on an explicit request.
