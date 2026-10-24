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
- Pretrained run outside the gate: `tests/full_rtl/evidence/clamp_census_20261024/results.json`. 96/96 tokens equal the reference on both simulators, `overflow_out=0`, and no activation clamp saturates. `overflow_out` stays linear-only; this is documented in `docs/design/host_interface.md`.
- Not run for this RTL: portable elaboration; gated application.

## Blocker for the gated pretrained-application claim

- `check_gate.py` needs `tests/full_rtl/unit_results.json` to be PASS. It must come from a local `run_units.ps1 -Questa` run (Questa Starter at `C:/altera_lite/25.1std/questa_fse/win64`) on the current RTL. The tracked file is still FAIL from 2026-10-07.
- The exporter and reference need Python 3.12, because the packages in `tests/language_demo/packages` are cp312. The documented runtime `C:/Users/khanh/.cache/codex-runtimes/.../python.exe` no longer exists, and only Python 3.14 is installed. Checkpoint assets are only in the main checkout (`D:/2151097_Nguyen Nhut Khanh/tests/language_demo/upstream`), not in this worktree.

## Next action

- With a Python 3.12 runtime: run the seven groups through `run_units.ps1` (fresh library/evidence tag). Then run `run_application.ps1` with `-TimingManifest docs/verification/timing/dead_states_fault_drain_20261024/manifest.json` as in `docs/demos/language.md`, and record the result in `docs/verification/optimization_status.md`.
