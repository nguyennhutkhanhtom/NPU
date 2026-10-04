# NPU resume checkpoint

Updated 2026-10-04 14:34 Asia/Saigon. Repo, raw reports and hashes are authoritative. Preserve valid changes and immutable evidence; no reset/revert.

## Goal and binding rules

Full graph and autoregressive selection on RTL. CPU loads weights/config/prompt and tokenizer/decode only. Pretrained application/reference inference requires exact-current all-seven tests PASS AND full-top post-fit >=100 MHz, all four corners setup/hold/recovery/removal/pulse slack>=0, TNS=0, UCP=0. No timing exceptions to mask failures; FPGA demo is not ASIC signoff.

[AGENTS.md](AGENTS.md): explicit RTL/generate replication; no synthesizable task, variable/unbounded loop or hidden sequential ownership; functions only small pure combinational helpers. Only vendor IP allowed is altsyncram behind the SRAM adapter. No compute/control/DSP/PLL/arithmetic IP or runtime multiply/divide operators.

## Current verified milestone

- main: pushed milestone `caed5605539f11fe0fd93dab74ead286f4cba8a1`. Earlier milestones retained. No trained application or CPU checkpoint inference has run.
- 33 RTL assets. Unused legacy controllers/helpers removed with stale QSF/source-guide entries; valid legacy tests retained. All 61 request/math/write task calls are visible FSM assignments; generated pipelines have one register owner. LUTs are combinational modules. Unsigned buffer/row casts preserve the former task argument contract. No added numeric/transaction latency.
- [All seven current groups PASS](tests/full_rtl/evidence/explicit3_all_units/results.json), completed 14:30:22: Questa2025.2 + official Quartus25.1 RAM; compile/runtime 0 warnings. Graph: prompt2, RTL-selected tokens3, layer executions16, causal checks, 4,229,462 compute clocks, 196,619 host commands. Synthetic fixture, not trained text. Archive has seven logs/binding reports, start/source/test/helper/model hashes and reproduction inputs. Six-group partial tag retained unchanged.
- [A&S PASS](docs/verification/synthesis/explicit2/manifest.json): current 33 RTL + 3 config files, 0 errors/12 warnings, completed13:37:42. This is not timing PASS.
- [Legacy ten groups PASS](tests/evidence/explicit2_legacy_units/results.json), 13:17:30, 0 runtime warnings. Archive is the pre-address-fix snapshot; the later llm_soc-only fix does not affect reachable legacy RTL.
- [Docs validation](docs/source_guide/validation.json): 33 assets/29 main diagrams/15 detail diagrams/147 groups/4504 RTL lines/1059 LUT lines/50 rendered diagrams. Rerun link validation after the current documentation edits.

## Active job: do not duplicate or edit its inputs

`fullrtl100_explicit2`, exec58640, supervisor35692, Fitter20468, isolated quartus_explicit2/llm_soc. Started13:22; placement/routing complete14:33, final fitter/STA pending. 33 RTL/QSF/QPF/SDC locked, source ZIP36 members already archived. Canonical config matches isolated config.

Quartus Lite25.1std.0 Build1129; CycloneV5CGXFC9E6F35C7, seed1/SPEED/STANDARD. SDC10ns/input0.5..2ns/outputsetup2ns/hold0.5ns, no exceptions; LF SHA aa4dc1a48cfd2aabd01770a0eb010b14a2abdfe2cfc9d69968a89b1172ccd181. QSF cache MAX_FANOUT2/op MAX_FANOUT16, physical duplication/high-fanout delay enabled; four unsupported input delay assignments removed. Ordinary clock/reset/SDR LVDS pins, no PLL/SERDES. Board pinout/termination not verified.

## Facts, failures and hypotheses

- [Timing hub](docs/verification/timing/README.md): logic5/6 both FAIL99.07MHz; logic7 FAIL96.04MHz. Setup/hold/removal failures, UCP0, DSP/PLL/DLL/HSSI0. All source/config/raw report tags retained. Logic7 source_hashes_verified=false after unused-source deletion; historical evidence only.
- Prior measured paths: cache/control fanout, host input hold, raw reset removal to packed output FFs. Current fanout settings require actual post-fit evidence. Portable reset-release conditioning is a possible next fix, not yet implemented or verified.
- Explicit1 compile failure and cancelled timing, explicit2 signed-address operator failure, legacy ROM-format/test-interface failures are archived. Fixes preserve expected numeric values; current seven groups PASS.
- Synthesis warnings: bounded generated LUT index10027, unused SRAM ports287013, intended token RAM forwarding276020, constant debug outputs13024/13410. Fitter license/pin/constant-output warnings explained in timing hub; timing332148 must be fixed.

## Tools and reproduction

Quartus C:/altera_lite/25.1std/quartus/bin64; Questa C:/altera_lite/25.1std/questa_fse/win64; ModelSim C:/intelFPGA/20.1/modelsim_ase/win32aloem. Python C:/Users/khanh/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe. Windows Application Control blocks unsigned helpers; do not bypass. Vendor model/library, weights and build DB stay ignored.

```powershell
Get-Content docs/verification/timing/fullrtl100_explicit2/fit.log -Tail 12
Get-CimInstance Win32_Process | Where-Object { $_.Name -match 'quartus|vsimk' } | Select ProcessId,ParentProcessId,Name,CommandLine
# Reproduce only after active timing finishes, with fresh tag/library:
./tests/full_rtl/run_units.ps1 -SimBin C:/altera_lite/25.1std/questa_fse/win64 -Questa -MemoryModelManifest tests/full_rtl/build/questa25_model/manifest.json -TimingManifest docs/verification/timing/fullrtl100_logic5/manifest.json -WorkLibraryName NEW_WORK -EvidenceTag NEW_TAG
./tools/timing/run.ps1 -Project quartus_explicit2/llm_soc -Tag NEW_TAG -QuartusBin C:/altera_lite/25.1std/quartus/bin64
python docs/source_guide/validate.py
# ONLY after exact-current hardware AND all-seven gates PASS:
./tests/full_rtl/run_application.ps1 -TimingManifest docs/verification/timing/PASS_TAG/manifest.json
```

## Next priorities

1. Finish current fitter/STA/all corners; verify hashes, resources, warnings and critical paths; preserve complete tag before editing RTL.
2. If FAIL, fix measured paths with portable RTL and rerun affected tests/full gates under fresh tags. Never infer timing PASS from synthesis PASS.
3. Validate current docs links/excerpts/render, archive and commit/push verified milestones. No large build artifacts/model/vendor libraries/secrets.
4. After gates: pinned NanoFable actual RTL generation, numeric/token comparison and decoded paragraph quality review; second compatible model when supported and hardware gates pass.
