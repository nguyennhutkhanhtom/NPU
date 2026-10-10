# Run the real NanoFable on llm_soc

<!-- reading-navigation:start -->
[Documentation](../README.md) → [00 · Start here](../00-start-here/README.md) → This page

| Reading guide | Document |
|---|---|
| Read first | [Demo reading flow](../00-start-here/demo-flow.md) |
| Continue / related lookup | [Current server application workflow](../../tools/server/README.md#application-checkpoint) |
<!-- reading-navigation:end -->

> Branch `remote`: the local commands in this document are historical. Run the checkpoint using [flow server](../../tools/server/README.md#application-checkpoint); do not use the old FPGA hardware gate for the new configuration.

> **Category: GUIDE.**

The runner uses the pinned checkpoint **NanoFable-1M-ternary seed1**. The host loads parameters,
prompt and configuration; all prefill/decode, attention, head, and token selection runs
in RTL simulation. Integer reference on the CPU is used to verify the output tokens.

## Before running

| Required | Value currently used on this workspace |
|---|---|
| Top | llm_soc; do not select matmulfree for this application |
| Python | 3.11 or 3.12 for pinned packages |
| Simulator | Questa Altera Starter 2025.2, in C:/altera_lite/25.1std/questa_fse/win64 |
| RAM model | altera_mf.v from the Quartus version recorded in timing manifest |
| Checkpoint/tokenizer | tests/language_demo/upstream, SHA-256 matches upstream_manifest.json |
| Evidence | All seven groups PASS and full-top all-corner timing reaches ≥100 MHz, correct RTL/config |

Current verification and application status: [optimization status](../verification/optimization_status.md). Only one Questa session is used each time because the application shares the build name.

## Steps to run

### 1. Open PowerShell in the repository

```powershell
Set-Location -LiteralPath 'D:/2151097_Nguyen Nhut Khanh'
$pythonExe = 'C:/Users/khanh/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
$simBin = 'C:/altera_lite/25.1std/questa_fse/win64'
& $pythonExe --version
```

The above paths point to the runtime and tools currently used in the workspace. When changing machines,
replace them with the corresponding installation. `setup.ps1` requires Python 3.11/3.12.

### 2. Prepare checkpoints and dependencies

If the assets already exist, just check the files:

```powershell
& $pythonExe tests/language_demo/fetch_assets.py --check
```

If assets or packages are missing, run the setup once:

```powershell
& tests/language_demo/setup.ps1 -Python $pythonExe
```

Setup installs NumPy, safetensors, and tokenizers into a separate packages folder, then download
and verify the 12 pinned files. This step does not execute checkpoint inference.

### 3. Select the correct manifest and check the gate

Only select the `manifest.json` file from a completed timing run. The manifest below
is a historical example; select the applicable manifest from the status page and check the gate before running.

```powershell
$timingManifest = 'docs/verification/timing/nanofable_max_20261006/manifest.json'
if (-not (Test-Path -LiteralPath $timingManifest)) {
    throw 'Timing has not completed. Check the workflow status/log or start a new timing run.'
}
& $pythonExe tests/full_rtl/check_gate.py $timingManifest
if ($LASTEXITCODE -ne 0) { throw 'Gate has not passed; stop before export and application.' }
```

Result to expect: `FULL_RTL_APPLICATION_GATE_PASS`. If source, tests, evidence
logs or QSF/QPF/SDC do not match, see [reverification method](../verification/README.md).
Do not change hash, timing limits, or expected tokens to pass the gate.

### 4. Short test run: 8 token greedy

```powershell
$appArgs = @{
    TimingManifest = $timingManifest
    Python = $pythonExe
    SimBin = $simBin
    Prompt = 'Once upon a time'
    NewTokens = 8
    MinNew = 8
    Temperature = 0
    Seed = 7
}
& tests/full_rtl/run_application.ps1 @appArgs
```

Runner checks gate, prepares model RAM, exports parameter image and reference,
compiles testbench, simulates, then verifies evidence. `MinNew=8` masks EOS in
8 token; `Temperature=0` uses greedy. Start with a short pass to know the pipeline
The application operates before selecting a long continuation.

To test the function when RTL has changed or timing/unit gate has not PASSED, skip
the step calling `check_gate.py` above and use:

```powershell
& tests/full_rtl/run_application.ps1 @appArgs -SkipGate
```

This mode still requires `TimingManifest` to select the Quartus RAM model and still
check that the RTL token matches the reference. The results are saved separately in
`tests/full_rtl/application_functional_results.json` (`hardware_gate: SKIPPED`)
and `tests/full_rtl/generated_functional_text.md`; it does not prove the timing or
seven unit groups have PASSED for the current RTL.

### 5. Run a longer continuation

After saving the previous results, replace the parameters in the same PowerShell:

```powershell
$appArgs.Prompt = 'Once upon a time, Lily found a tiny kitten.'
$appArgs.NewTokens = 96
$appArgs.MinNew = 64
$appArgs.Temperature = 166
& tests/full_rtl/run_application.ps1 @appArgs
```

Temperature uses raw U8/F8 format: 166 corresponds to about 0.6484. EOS can terminate
after `MinNew`; not every time does it generate `NewTokens`. Exporter check
`prompt token count + NewTokens ≤128`; the number of prompt tokens is not the number of words.
Choose a short English prompt for this storytelling checkpoint. The simulation length on PC
depends on the prompt/context and the number of tokens, different from time calculated by hardware clock.

### 6. Use up the current RTL context

The original checkpoint declares the context **512 tokens** in `upstream/config.json`.
The current RTL supports **128 tokens**, including prompt and continuation. Therefore,
demo of this RTL's maximum using prompt `Once upon a time` (4 tokens) and generating
124 new tokens; this is the limit of the RTL being verified.

```powershell
$appArgs.Prompt = 'Once upon a time'
$appArgs.NewTokens = 124
$appArgs.MinNew = 124
$appArgs.Temperature = 166
$appArgs.Seed = 7
& tests/full_rtl/run_application.ps1 @appArgs
```

`MinNew=124` keeps the masked EOS throughout the continuation to use all 128 positions.
This is the sampling configuration; the resulting tokens must still match the integer reference.
To use the full 512 context of the checkpoint, the RTL, memory/address geometry,
exporter and testbench need to be expanded, then rerun the gates before the application.

## Reading progress and results

Open a second terminal in the repository if you want to see the log during simulation:

```powershell
Get-Content -LiteralPath 'tests/full_rtl/build/application.log' -Tail 20 -Wait
```

Ctrl+C in the monitoring terminal only stops `Get-Content`; to stop the simulation, use
The terminal is running the runner. The log reports `FULL_RTL_LOAD_PROGRESS` every 1,024 parameters
rows while loading the checkpoint, then `FULL_RTL_GRAPH_START` when starting inference.
The log reports `FULL_RTL_PROGRESS` every 100,000 compute clocks and
`FULL_RTL_TOKEN_VERIFIED` for each token compared. The runner stops immediately on mismatch.

| File | Content |
|---|---|
| tests/full_rtl/generated_text.md | Continuation decode from actual RTL tokens |
| tests/full_rtl/application_results.json | PASS, token IDs, RTL text, source/evidence hashes, and text_quality |
| tests/full_rtl/build/rtl_tokens.txt | Token IDs read by host from output window |
| tests/full_rtl/build/application.log | Runtime log and FULL_RTL_APPLICATION_PASS |
| tests/full_rtl/build/application_compile.log | Compile diagnostics |
| tests/full_rtl/build/reference.json | Input config and expected continuation of reference integer |

A full pass requires `FULL_RTL_APPLICATION_PASS` and
`FULL_RTL_APPLICATION_EVIDENCE_PASS`. `application_results.json` records `status=PASS`
when RTL token matches reference. Item `text_quality=NOT_ASSESSED` needs to be supplemented
by reading the actual paragraph; PASS numeric has not confirmed text quality.

## Save results before the next pass

The runner currently shares the build folder and output files for multiple application runs.
Before running again, save a new archive, for example:

```powershell
$appArchive = 'tests/full_rtl/evidence/my_nanofable_20261006'
if (Test-Path -LiteralPath $appArchive) { throw 'Choose an archive name that does not already exist.' }
New-Item -ItemType Directory -Path $appArchive | Out-Null
Copy-Item -LiteralPath 'tests/full_rtl/application_results.json','tests/full_rtl/generated_text.md' -Destination $appArchive
$appFiles = @('application_compile.log','application_compile.console','application.log',
    'application.log.console','reference.json','rtl_tokens.txt','application_design_units.json',
    'parameter.mem','prompt.mem','expected.mem','config.svh','application_sources.f')
foreach ($name in $appFiles) {
    Copy-Item -LiteralPath (Join-Path 'tests/full_rtl/build' $name) -Destination $appArchive
}
$hashes = [ordered]@{}
Get-ChildItem -LiteralPath $appArchive -File | ForEach-Object {
    $hashes[$_.Name] = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
}
$hashes | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $appArchive 'sha256.json') -Encoding utf8
```

This archive stores results/log/input, while timing and source snapshots are referenced through
the manifest. Keep the RAM-model cache referenced by the application result. Do not modify
the old archive to represent a different run.

## When the runner stops

| Message / Situation | Handling |
|---|---|
| Missing manifest or Configuration changed after timing | Wait/create full-top timing for the current configuration and then check the gate |
| RTL changed or unit evidence stale | Rerun the affected unit/graph or timing; keep the old evidence |
| Missing pinned asset / import error | Run setup with Python 3.11/3.12 or check assets/packages |
| License unavailable | End the current Questa session using the license before opening a new session |
| Prompt exceeds context | Reduce the prompt or NewTokens; keep total tokens ≤128 |
| Token mismatch, timeout or error | Keep log/input/reference for debugging; do not change expected IDs or watchdog to get PASS |

[Host map](../design/host_interface.md) explains what the testbench writes into the DUT.
[Old hybrid report](legacy/nanofable_hybrid.md) records CPU generation and linear-only
Previous RTL; that result belongs to a different flow than this application.
