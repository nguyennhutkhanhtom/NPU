# Reproducible Quartus timing demo

[Documentation hub](../../docs/README.md) · [Verification](../../docs/verification/README.md)

## Compile, extract and archive

Use Python 3 and the installed Quartus Lite25.1std for current full-top builds;
older archived tags used18.1. The paths can be supplied explicitly; Python
and Quartus on `PATH` are otherwise used. The Python helper needs no third-party
packages.

`archive_sources.py` adds a compact source ZIP only when every RTL byte hash
matches `sources_before.json`; it refuses to overwrite earlier archives.
Configuration uses the recorded canonical LF hashes. For example, while inputs
remain unchanged:

```powershell
python tools/timing/archive_sources.py --evidence docs/verification/timing/NEW_TAG --rtl-dir 'Verilog Source code'
```

Extract into a separate reproduction folder and rename the archive's `rtl`
folder to `Verilog Source code` so the recorded QSF relative paths resolve.
`source_archive.json` records the ZIP hash, input snapshot hash and every member
hash. `fullrtl100_tiled` was recovered from the preserved signed candidate by
restoring its single attention part-select line; **all original byte hashes**
were checked before archiving. This recovery adds provenance without changing
any earlier timing manifest/report.

```powershell
./tools/timing/run.ps1 -Project quartus/llm_soc -Tag replay-01 -QuartusBin 'C:/altera_lite/25.1std/quartus/bin64'
```

The runner compiles the existing project using its QSF and SDC, runs post-fit
STA, extracts all four timing corners, then archives evidence under
`docs/verification/timing/replay-01`. It preserves earlier evidence: choose a
fresh `-Tag` for each run. Override `-Project`, `-RtlDir` and `-Python` as needed.
The QSF source assignments must resolve inside the selected RTL directory.

For the separate immutable baseline project:

```powershell
./tools/timing/run.ps1 -Project tests/sim/timing_baseline_build/matmul_free -RtlDir tests/sim/timing_baseline_build/rtl -Tag baseline-replay-01 -QuartusBin 'C:/intelFPGA_lite/18.1/quartus/bin64'
```

Before compilation, `sources_before.json` records all current RTL/source assets and the
QPF/QSF/SDC. Recording evidence checks them again and fails if inputs changed.
Each stage must report successful completion and produce fresh reports; a
successful exit code alone cannot reuse reports left by an earlier compile.
RTL hashes are byte-exact; configuration comparison normalizes CRLF to LF
because Quartus may rewrite project line endings. Map and fit use
`--write_settings_files=off`; STA uses its supported project/revision arguments.
The extractor closes the project with `-dont_export_assignments`.

`manifest.json` records actual corner Fmax, setup/hold/recovery/removal/pulse
slacks, worst setup/hold endpoints and data delays, unconstrained endpoint
counts, fitted resources and stage error/warning totals. The six map/fit/STA
reports and summaries are archived with raw and LF-normalized hashes. A flow
report from an older compilation is not included.
`TIMING_STAGE_PASS` means that a Quartus tool stage completed. Evidence recording
prints `TIMING_EVIDENCE_RECORDED`, then a separate `TIMING_100MHZ_PASS/FAIL`;
the latter requires all four corners, all five timing checks, TNS0 and no
unconstrained paths. It does not replace the seven-unit application gate.
The source snapshot is copied into the evidence directory and hashed in the
manifest, including when a manual run originally kept it under an ignored
build directory. Runner command arguments are recorded and hashed as well.

To record a completed manual compile after extraction, use its source snapshot:

```powershell
python tools/timing/record.py --project tests/sim/timing_baseline_build/matmul_free --rtl-dir tests/sim/timing_baseline_build/rtl --output docs/verification/timing/constrained_baseline --source-snapshot tests/sim/timing_baseline_build/baseline_sources.json
```

The older baseline snapshot verifies RTL hashes. Its manifest explicitly marks
that pre-compile configuration hashes were unavailable. New runner snapshots
verify both source and configuration hashes.

## Extract from an existing routed database

`extract.tcl` reads the current routed Quartus database. Run a full compile first
when RTL, constraints or fitter settings have changed. Extraction does not run
synthesis or placement/routing and does not edit the QSF or SDC.

From the repository root, with Quartus 18.1 installed:

```powershell
& 'C:/intelFPGA_lite/18.1/quartus/bin64/quartus_sta.exe' -t tools/timing/extract.tcl docs/verification/timing/user_baseline 1.0
```

The numeric argument specifies a clock period in ns. `1.0` reproduces the user's
original automatic clock constraint for diagnostic comparison. It leaves I/O
unconstrained, matching that original report. It is not a signoff constraint.

For a routed compile that used the project's explicit SDC:

```powershell
& 'C:/intelFPGA_lite/18.1/quartus/bin64/quartus_sta.exe' -t tools/timing/extract.tcl docs/verification/timing/constrained sdc
```

An optional third argument selects another existing project, for example an
immutable baseline checkout built with the same clock, fitter settings and seed:

```powershell
& 'C:/intelFPGA_lite/18.1/quartus/bin64/quartus_sta.exe' -t tools/timing/extract.tcl docs/verification/timing/constrained_baseline sdc tests/sim/timing_baseline_build/matmul_free.qpf
```

Each of the four models (slow/fast, 0/85 °C, 1.1 V) gets 40 setup and hold paths,
recovery/removal paths when present, pulse-width and Fmax reports. Additional
reports record constraints, unconstrained endpoints and timing checks. Closure
recommendations are exported as text and HTML when the installed Quartus
heuristics support the current database. The recommendation exporter uses the
bundled Quartus 18.1 analysis Tcl; a different release may require an update.

The archived [user baseline](../../docs/verification/timing/user_baseline/manifest.json)
records raw source and LF-normalized archive hashes. FPGA Fmax and timing are
specific to this device, compilation and timing model; they do not establish
ASIC timing or board interface closure.
