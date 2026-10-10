# RTL coding readiness review — 2026-10-10

<!-- reading-navigation:start -->
[Documentation](../README.md) → [Decisions](../decisions/README.md) → This page

| Reading guide | Document |
|---|---|
| Read first | [Execution contract](../NPU_V2_EXECUTION.md) |
| Continue / related lookup | [Matching verification evidence](../verification/optimization_status.md) |
<!-- reading-navigation:end -->

Scope: the current `llm_soc` graph, its arithmetic/memory/reset leaves, packages
and included LUT definitions. Legacy top/control is outside this refactor.
The user's primary reference is the [lowRISC Verilog Coding Style Guide](https://github.com/lowRISC/style-guides/blob/master/VerilogCodingStyle.md).
[EcrioniX](https://ecrionix.org/rtl_design/coding-guidelines/) is secondary.
Repository behavior, numeric contracts and evidence remain authoritative.

## Implemented

- All ports retain their original `input logic` spelling. No new `input wire`
  declarations or nettype directives remain. LUT headers and their generator
  have also returned to their original declarations/content.
- Nine files use SystemVerilog generate constructs without optional
  `generate`/`endgenerate` regions. Bounds, branches and explicit names are retained.
- `llm_head_engine` names the fixed row count, result capacity, final chunk and
  scale lane, and references `llm_pkg::EMB_SCALE_BASE`. Counter comparisons and
  assignments have explicit constant sizing. Result arrays use the existing
  eight-slot geometry. Updates are laid out individually with two-space nesting
  and blocks around wrapped statements.
- Six `llm_pkg` constants use package `parameter` declarations. Their signed
  32-bit types and values are unchanged; package parameters are not overridable.
- All eleven modified module/package guides are synchronized. Architecture
  and diagrams have not changed.

## Retained behavior and exceptions

| Location | Retained code / reason |
|---|---|
| `sram_word_tile`, memory adapters | Memory contents and committed writes survive reset. Adding array reset logic would change this contract and memory implementation. Reset control/validity remains explicit. |
| `llm_math`, engines, `llm_soc` payload stages | Unreset payload and continuously clocked arithmetic stages are qualified by validity. Adding reset or replacing the existing pipeline enables requires a hardware/PPA change. |
| `llm_soc` operator control | Explicit one-hot `op` state bits and sequential transitions remain. Converting this to an enum/two-process FSM requires a separate equivalence and mapped implementation review; it is not a mechanical rename. |
| RAM wrapper `ADDR_W` parameters | Preserve existing overridable interfaces and named caller overrides. Changing a derived header parameter to `localparam` would remove configuration support. |
| Existing ports/registers/generate labels | Preserve integration names and hierarchical testbench probes. Names can be migrated with all users updated; there is no demonstrated synthesis reason that prevents renaming. |
| Existing plain `case` with defaults | Preserve exact default and priority behavior. A blanket `unique` conversion is not justified without reviewing mutual-exclusion assumptions and diagnostics. |

These are scoped project decisions, not proof that equivalent redesigns are
impossible. No formal equivalence or mapped-quality improvement is claimed.
The FSM/interface decisions above are documented here while the measured
snapshot is frozen; any future exception comments must be included in a new
snapshot and its verification.

The existing `wire ... = expression` declarations are continuous assignments,
which lowRISC explicitly permits. They must not be mechanically changed to
`logic ... = expression`, which would be variable initialization. Integer
variables in `logic_mul` compute elaboration geometry; narrowing them would not
remove runtime hardware. Fixed graph dimensions and structural multiply/divide
logic implement the numeric contract, not style defects.

**Secondary-guide exception:** newly added `default_nettype none` guards were
removed to preserve the user's requested `input logic` spelling. Xcelium 24.09
diagnoses the omitted ANSI input net kind under that directive (NODNTW); placing
the directive inside a module is illegal (BADDNZ). The valid final source uses
its original explicitly typed port declarations and compiler defaults. lowRISC
requires explicit signal declarations but does not mandate this directive.
No simulator diagnostics are waived. Existing `postscale` declarations/directives
are outside this change and remain untouched.

## Remaining style work

This pass does **not** establish complete lowRISC lint compliance. Existing
files still contain four-space indentation, long/compact lines, unsized literals,
unlabelled conditional generate branches and older register/enum/port naming.
These are generally fixable; they are not synthesis-based exemptions. Continue
with a bounded, token-preserving formatting/naming pass after the current jobs
finish, then separately review FSM structure and type/width changes. Do not
alter the snapshot while EDA measures it.

## Verification and provenance

Static checks: `tests/full_rtl/build/scratchpad/rtl_guidelines_20261010/static_checks.json`.
Twenty reviewed sources preserve hardware tokens after optional-region
normalization (some are now entirely unchanged). The head engine preserves its parsed statement/control tree after
checked constant expansion and normalization of single-statement blocks.
All 24,592 representable unsigned comparator cases agree; zero-extension also
preserves four-state comparison behavior. Package constant types/values match.
The exp/Gumbel headers and generator have no final changes. This is a static
refactor check, not a full HDL parser, simulation or synthesis PASS.

Frozen local inputs: `tests/full_rtl/build/bundle_lowrisc4_20261010/bundle_manifest.json`.
Remote root: `/home/yellow/ee5303_09/project/test_khanh/bundle_lowrisc4_20261010`.
Current-source Xcelium verification is complete: scoped operators job 64471 and
all nine full-graph groups in job 64472 pass with zero simulator diagnostics.
All 60 input hashes match both frozen and current source; all 5 scoped and 37
full report hashes match. [Verified receipt](../../tests/full_rtl/evidence/lowrisc_20261010/verification_review4.json).
Genus job 64473 is In progress on `black.doelab.site`; workflow PID 3151889
and synthesis launcher PID 3153368 identify the running allocation.
The approved workflow runs scoped operators, then all nine full-graph groups,
then full-top Genus with mandatory X11 and the existing 10 ns constraint.
Genus is configured for 352 intended SRAM black boxes; confirm the final report.
Compare mapped cell count/area,
timing and diagnostics against the matching Phase 1C baseline only after report
and source hashes are verified. SRAM area/timing and physical closure remain
outside this flow.

Prior launch `bundle_rtl_guidelines_20261010` failed before EDA because the PDK
is not mounted on the login node. Its log is preserved. The replacement workflow
checks the approved library hash and actual Genus module on a Slurm compute node.
The first lowRISC scoped job 64466 reached the 113,131-check operators PASS marker
but correctly failed the diagnostics gate on Xcelium NODNTW warnings for implicit
ANSI input net kinds. The explicit `wire logic` snapshot passed scoped/full jobs
64467/64468 with zero simulator diagnostics and all 60 input/5 or 37 report hashes
verified. At the user's request, ports were restored to `input logic`. An attempted
body guard was rejected by the compiler and removed. These earlier PASS records are
preserved as superseded evidence, not current-source PASS. Only our identified
obsolete synthesis job 64469 was cancelled. Matching verification now uses fresh
`lowrisc_*4_20261010` tags. The failed warning attempt remains under `failed_scoped`;
the invalid directive run 64470 is preserved remotely in `bundle_lowrisc3_20261010`.
Continuation and exact monitoring commands are in
`tests/full_rtl/build/scratchpad/rtl_guidelines_20261010/handoff.md`.
