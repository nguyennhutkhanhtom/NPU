# Full-top timing and NanoFable demo in the maximum RTL context

<!-- reading-navigation:start -->
[Documentation](../README.md) → [Archive](../archive/README.md) → This page

| Reading guide | Document |
|---|---|
| New to the subject | [NPU and RTL fundamentals](../00-start-here/fundamentals.md) · [Glossary](../00-start-here/glossary.md) |
| Read first | [Historical context](../archive/README.md) |
| Continue / related lookup | [Current evidence](optimization_status.md) |
<!-- reading-navigation:end -->

> **Category: HISTORICAL SNAPSHOT — 2026-10-06.** Results below refer only to this saved run; use [current status](optimization_status.md) for workspace applicability.

## Scope and timing results

The verified top is `llm_soc`, with four attention divider lanes and four sigmoid
lanes; performance counters and opcode debug index are off. No changes to RTL, LUT,
QSF/QPF/SDC, timing constraints, or numeric expectations in this run.

Quartus Prime Lite 25.1std.0 has completed synthesis, fit, STA, and extraction.
[Timing manifest](timing/nanofable_max_20261006/manifest.json) verifies all 41
RTL/LUT assets and current configuration. The lowest Fmax is **100.78 MHz**, reaching gate
100 MHz at all four corners. The numbers below are post-fit FPGA timing from the backend
EDA; not ASIC signoff results or board run results.

| Corner (1.100 mV) | Restricted Fmax MHz | Setup ns | Hold ns | Recovery ns | Removal ns | Pulse ns |
|---|---:|---:|---:|---:|---:|---:|
| Slow 85 °C | 100,78 | +0,077 | +0,245 | +0,123 | +1,599 | +3,600 |
| Slow 0 °C | 101,50 | +0,148 | +0,232 | +0,332 | +3,666 | +3,548 |
| Fast 85 °C | 148,41 | +3,262 | +0,131 | +4,535 | +2,330 | +3,801 |
| Fast 0 °C | 161,60 | +3,812 | +0,115 | +5,473 | +0,976 | +3,790 |

TNS of all checks is **0**. All six unconstrained/illegal clock, input and
output groups have setup/hold count **0**. The worst setup path is
`vector_q[383] → input_cache_q[6][383]`, with a data delay of 9.627 ns at Slow 85 °C.
Margin +0.077 ns is still small; changing the source or backend requires re-measurement.

| Fitted resource | Quantity |
|---|---:|
| ALMs | 59.605 |
| Registers | 66,924 |
| Block memory bits | 9,516,544 |
| RAM blocks | 1.186 |
| DSP blocks | 0 |
| Pins | 186 |

Synthesis started at 01:28:33, fitting started at 01:34:09, STA started at 02:22:37 and
extraction started at 02:24:35 on 06/10/2026 (Asia/Saigon).
[Commands](timing/nanofable_max_20261006/commands.json) keep the UTC timestamp and
actual arguments. The assistant only reads the log/report after the entire Quartus flow
is completed; during execution, it only monitors process metadata.

## Gate and diagnostics

`FULL_RTL_APPLICATION_GATE_PASS: Fmax=100.78 MHz` was confirmed earlier
export/reference checkpoint. [Unit result](../../tests/full_rtl/unit_results.json)
all seven groups PASS: RAM technology, math, RAM, protocol, selection, operators
and autonomous graph. Source, tests, runner, and log/binding hashes still match.

Synthesis has 0 errors/22 warnings; fitter has 0 errors/4 warnings, including one
Critical Warning about pin locations; STA has 0 errors/0 warnings. Diagnostics
are kept unchanged in the report, without adding suppression or timing exception.

| Diagnostic | Evaluation in this completion round |
|---|---|
| 10036, 10027, 287013, 276020, 13024 | Along with types already [reviewed from the previous round](warning_review_nanofable_20261005.md): state not used, index with deliberately narrow range, vendor RAM inputs, read-during-write forwarding, and debug constants. RTL and unit evidence unchanged. |
| 292013 | LogicLock limit of Quartus Lite license, belonging to backend. |
| 15714, Critical Warning 169085 | Missing board I/O/pin locations for 125 pins. This is an EDA demonstration; do not place fake board pinout into portable RTL. Timing and unconstrained checks still need to PASS. |
| 176251 | Wildcard Fast Output Register for `pc_debug[*]` and `instr_debug[*]` has some invalid destinations; the debug buses have constant bits. Quartus ignores those targets. All output timing is still checked and PASS. The assignment belongs to QSF, not portable compute/control. |

## Demo configuration

Checkpoint is NanoFable-1M-ternary seed1 already pinned; 12 assets have passed SHA-256 check.
The original checkpoint declared a **512 token** context, while the current RTL supports **128**.
According to the selected scope, the demo uses the full context of RTL:

| Parameter | Value |
|---|---|
| Prompt | `Once upon a time` |
| Prompt IDs | 433, 449, 261, 398 |
| Prompt tokens | 4 |
| NewTokens / MinNew | 124 / 124 |
| Total context | 128 |
| Temperature | 166 (U8/F8, approximately 0.6484) |
| Seed | 7 |

`MinNew=124` mask EOS to use full budget. CPU host loads parameter/prompt and reads
results; all prefill/decode, attention, head and token selection run on RTL.
Integer reference used to compare tokens, does not control DUT.

## Application results

**Running**, final application PASS not yet available. Reference has been fully prepared
124 continuation tokens; simulation must check all tokens and provenance
before concluding. Text quality will be evaluated after decoding RTL tokens.

Workflow and execution configuration (`../../tests/full_rtl/evidence/nanofable_max_20261006/workflow.ps1`; historical target unavailable in this checkout)
and status (`../../tests/full_rtl/evidence/nanofable_max_20261006/status.json`; historical target unavailable in this checkout)
maintain the progress of the new run. An old worker only waits for the manifest to be stopped to
avoid running applications in parallel; the status before stopping is maintained in
the new evidence. Evidence from previous runs is not reset or overwritten by this run.

## Reproduce

[NanoFable Guide](../demos/language.md) has gate and application commands.
The workflow of this run executes the manifest and sampling config above correctly. Choose a new tag
for the next run; do not overwrite old evidence. Only commit/push the results
after the application is completed and the checks pass.
