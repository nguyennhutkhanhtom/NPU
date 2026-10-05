# Exact optimization verification status

Implementation report: [version 3](../reviews/rtl_change_review_v3.md).
Architecture: [resource and latency contracts](../design/exact_throughput_optimization.md).

Current RTL implements the approved exact arithmetic/control/cache/streaming changes.
No pretrained application has been executed by this task.
The final audit matches all 41 current RTL/LUT hashes across unit, host,
portable and timing evidence, verifies all three backend configuration hashes,
and confirms integrity of the 80-file final unit archive and timing report archive.

## Completed final checks

- All-seven synthetic regression: [PASS](../../tests/full_rtl/evidence/opt_final4_all/results.json),
  library/tag `opt_final4`, zero compile/runtime warnings. Graph: 1,066,965 compute
  clocks, 3.987x faster than the matching 4,254,046-clock baseline; same three
  tokens, sixteen layer executions, causal checks and exact traffic totals.
- Full-top synthesis/fit/STA: [PASS](timing/opt_fulltop7/manifest.json), minimum
  all-corner Fmax 100.78 MHz; worst setup +0.077 ns, hold +0.115 ns. Setup,
  hold, recovery, removal and pulse-width slack are nonnegative at all four
  corners, every TNS is zero, and there are no unconstrained paths/ports/clocks.
  Current source and configuration hashes are verified. SDC, device, seed,
  ALL worker concurrency and physical delay settings match the task-start backend.
  Fitted resources: 59,605 ALMs (+10.43%), 66,924 registers (+20.66%), 1,186
  RAM blocks (unchanged), zero DSP blocks. Synthesis has 22 warnings, fitting
  four retained backend warnings; STA and extraction have zero errors/warnings.
- Current-source host cancellation: [PASS](../../tests/full_rtl/evidence/opt_host1/results.json).
- Vendor-free elaboration: [PASS](portable_elaboration_opt_final4/results.json),
  zero errors/warnings, no vendor memory/control/arithmetic modules loaded.

Intermediate checkpoints and failures are preserved in `tests/full_rtl/evidence/opt_*`
and `docs/verification/timing/opt_fulltop*`. Partial or interrupted attempts do not
establish all-seven PASS or timing closure.

## Reproduction commands

Use fresh library names and evidence tags; existing evidence must not be overwritten.

```powershell
& tests/full_rtl/run_units.ps1 -SimBin C:/altera_lite/25.1std/questa_fse/win64 -Questa -MemoryModelManifest tests/full_rtl/build/questa25_model/manifest.json -TimingManifest docs/verification/timing/opt_fulltop7/manifest.json -WorkLibraryName FRESH_LIBRARY -EvidenceTag FRESH_TAG
& tools/timing/run.ps1 -Project quartus/llm_soc -Tag fresh_timing -QuartusBin C:/altera_lite/25.1std/quartus/bin64 -Python C:/Users/khanh/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe
& tests/full_rtl/run_host_cancel_100mhz.ps1 -WorkLibraryName FRESH_HOST_LIBRARY -EvidenceTag FRESH_HOST_TAG
& tests/full_rtl/run_portable_100mhz.ps1 -WorkLibraryName ALL_SEVEN_LIBRARY -EvidenceTag FRESH_PORTABLE_TAG
```

The exact-current hardware prerequisites for the application gate now PASS for the
default four divider/four sigmoid lanes. No pretrained application or reference
inference was executed. Task-specific RTL change is (828 additions + 265 deletions)
/ 5,165 baseline code lines = 21.161665%, excluding comments, blank lines and
pre-existing changes. Quartus results are an EDA demonstration, not ASIC signoff.
