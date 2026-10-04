# NPU resume checkpoint

Updated 2026-10-04 15:02 Asia/Saigon. Repo, raw reports and hashes are authoritative. Preserve valid changes and immutable evidence; no reset/revert.

## Goal and binding rules

Full graph and autoregressive selection on RTL. CPU loads weights/config/prompt and tokenizer/decode only. Pretrained application/reference inference requires exact-current all-seven tests PASS AND full-top post-fit >=100 MHz, all four corners setup/hold/recovery/removal/pulse slack>=0, TNS=0, UCP=0. No timing exceptions to mask failures; FPGA demo is not ASIC signoff.

[AGENTS.md](AGENTS.md): explicit RTL/generate replication; no synthesizable task, variable/unbounded loop or hidden sequential ownership; functions only small pure combinational helpers. Only vendor IP allowed is altsyncram behind the SRAM adapter. No compute/control/DSP/PLL/arithmetic IP or runtime multiply/divide operators.

## Current verified milestone

- main: pushed milestone `49e9b72`. Earlier milestones retained. No trained application or CPU checkpoint inference has run.
- Preceding verified snapshot: 33 RTL assets. Unused legacy controllers/helpers removed with stale QSF/source-guide entries; valid legacy tests retained. All 61 request/math/write task calls are visible FSM assignments; generated pipelines have one register owner. LUTs are combinational modules. Unsigned buffer/row casts preserve the former task argument contract. No added numeric/transaction latency.
- [All seven preceding groups PASS](tests/full_rtl/evidence/explicit3_all_units/results.json), completed 14:30:22: Questa2025.2 + official Quartus25.1 RAM; compile/runtime 0 warnings. Graph: prompt2, RTL-selected tokens3, layer executions16, causal checks, 4,229,462 compute clocks, 196,619 host commands. Synthetic fixture, not trained text. Archive has seven logs/binding reports, start/source/test/helper/model hashes and reproduction inputs. Six-group partial tag retained unchanged.
- [A&S PASS](docs/verification/synthesis/explicit2/manifest.json): current 33 RTL + 3 config files, 0 errors/12 warnings, completed13:37:42. This is not timing PASS.
- [Legacy ten groups PASS](tests/evidence/explicit2_legacy_units/results.json), 13:17:30, 0 runtime warnings. Archive is the pre-address-fix snapshot; the later llm_soc-only fix does not affect reachable legacy RTL.
- [Docs validation](docs/source_guide/validation.json): 34 assets/30 main diagrams/15 detail diagrams/150 groups/4523 RTL lines/1059 LUT lines/51 rendered diagrams/1861 links. Link validation rerun after documentation edits; no diagram source changed.

## Active current candidate: 34 assets, gates pending

- Added reset_release: two explicit standard FFs, async assertion/two-edge sync release. All llm_soc internal reset consumers use core_rst_n. No IP/clock/exception added.
- SIMD partial/pair/product/reduction/sum payload FFs run continuously from captured operands. Start/busy/done/9-clock response and numeric widths unchanged; no wide valid_q enable.
- Timing fullrtl100_release1 RUNNING, exec85577, supervisor45288/map34380 completed14:58:51, fitter36936 active, isolated quartus_pipeline1/llm_soc. Snapshot34RTL+3config and source ZIP37members archived. [A&S archive](docs/verification/synthesis/release1/manifest.json) PASS0errors12warnings. Canonical QSF differs only by reset_release source assignment; SDC unchanged. Do not edit RTL/config or duplicate build.
- All-seven regression pipeline3 RUNNING, exec63509, work pipeline3_questa_work, official Questa2025.2/RAM25.1. Compile0errors0warnings; all six groups PASS, operators17/checks3460/scalar128/clamp128 completed14:58:02, graph38048 (supervisor42936) RUNNING. [Six-group archive](tests/full_rtl/evidence/pipeline3_six_units/results.json). Do not edit its eight test inputs/run_units/memory_model until done. Initial snapshot tests/full_rtl/build/pipeline3_modelsim_start.json.
- Pipeline1 failed elaboration: mechanical reset rename changed seven child port names. Archived pipeline1_port_binding_failed, fixed .rst_n(core_rst_n). Pipeline2 operator fixture FAIL: seeded token before the new release edges reset it to0. Archived pipeline2_reset_fixture_failed; fixture now releases reset fully before deposits/seeding. Same expected values and exact arithmetic latency checks. All17operators now PASS confirms fixture fix; graph pending.

## Complete preceding timing gate: FAIL

[fullrtl100_explicit2](docs/verification/timing/fullrtl100_explicit2/manifest.json) completed14:44:42; its jobs are closed. Exact 33 RTL + three config files verified against initial snapshot and all-seven unit archive. Source ZIP36 members/report/command hashes verified. Map0errors12warnings/fit0errors4warnings/STA0errors2timing warnings. Fmax93.28MHz; slow85 setup-.720/TNS-29.655, removal-.136/-4.137; slow0 setup-.234/-2.973, removal-.149/-5.290. Other16checks PASS/UCP0. 52189ALM/48316FF/1186RAMblocks/9515648bits/186pins, DSP/PLL/DLL/HSSI0. Application gate explicitly rejected Fmax below100MHz; no application ran.

Quartus Lite25.1std.0 Build1129; CycloneV5CGXFC9E6F35C7, seed1/SPEED/STANDARD. SDC10ns/input0.5..2ns/outputsetup2ns/hold0.5ns, no exceptions; LF SHA aa4dc1a48cfd2aabd01770a0eb010b14a2abdfe2cfc9d69968a89b1172ccd181. QSF cache MAX_FANOUT2/op MAX_FANOUT16, physical duplication/high-fanout delay enabled; four unsupported input delay assignments removed. Ordinary clock/reset/SDR LVDS pins, no PLL/SERDES. Board pinout/termination not verified.

## Facts, failures and hypotheses

- [Timing hub](docs/verification/timing/README.md): logic5/6 both FAIL99.07MHz; logic7 FAIL96.04MHz. Setup/hold/removal failures, UCP0, DSP/PLL/DLL/HSSI0. All source/config/raw report tags retained. Logic7 source_hashes_verified=false after unused-source deletion; historical evidence only.
- Prior measured paths: cache/control fanout, host input hold, raw reset removal to packed output FFs. Current worst setup is u_math.valid_q[0] to partial_q, data10.458ns/routing9.749ns/zero logic levels. Hold now passes all corners. Next fix: remove redundant wide payload enables while preserving captured-input/done contract; explicit two-FF async-assert/sync-release reset conditioner. Both fixes are implemented in the active candidate; fresh full gates are pending.
- Explicit1 compile failure and cancelled timing, explicit2 signed-address operator failure, legacy ROM-format/test-interface failures are archived. Fixes preserve expected numeric values; current seven groups PASS.
- Synthesis warnings: bounded generated LUT index10027, unused SRAM ports287013, intended token RAM forwarding276020, constant debug outputs13024/13410. Fitter license/pin/constant-output warnings explained in timing hub; timing332148 must be fixed.

## Tools and reproduction

Quartus C:/altera_lite/25.1std/quartus/bin64; Questa C:/altera_lite/25.1std/questa_fse/win64; ModelSim C:/intelFPGA/20.1/modelsim_ase/win32aloem. Python C:/Users/khanh/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe. Windows Application Control blocks unsigned helpers; do not bypass. Vendor model/library, weights and build DB stay ignored.

```powershell
Get-Content docs/verification/timing/fullrtl100_release1/map.log -Tail 12
Get-CimInstance Win32_Process | Where-Object { $_.Name -match 'quartus|vsimk' } | Select ProcessId,ParentProcessId,Name,CommandLine
# Reproduce only after active timing finishes, with fresh tag/library:
./tests/full_rtl/run_units.ps1 -SimBin C:/altera_lite/25.1std/questa_fse/win64 -Questa -MemoryModelManifest tests/full_rtl/build/questa25_model/manifest.json -TimingManifest docs/verification/timing/fullrtl100_logic5/manifest.json -WorkLibraryName NEW_WORK -EvidenceTag NEW_TAG
./tools/timing/run.ps1 -Project quartus_pipeline1/llm_soc -Tag NEW_TAG -QuartusBin C:/altera_lite/25.1std/quartus/bin64
python docs/source_guide/validate.py
# ONLY after exact-current hardware AND all-seven gates PASS:
./tests/full_rtl/run_application.ps1 -TimingManifest docs/verification/timing/PASS_TAG/manifest.json
```

## Next priorities

1. Finish pipeline3 regression and release1 full-top hardware gates. Archive partial/final results before any new edits; verify all source/config/model/report hashes.
2. If FAIL, fix measured paths with portable RTL and rerun affected tests/full gates under fresh tags. Never infer timing PASS from synthesis PASS.
3. Validate current docs links/excerpts/render, archive and commit/push verified milestones. No large build artifacts/model/vendor libraries/secrets.
4. After gates: pinned NanoFable actual RTL generation, numeric/token comparison and decoded paragraph quality review; second compatible model when supported and hardware gates pass.
