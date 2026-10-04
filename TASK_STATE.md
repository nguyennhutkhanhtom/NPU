# NPU resume checkpoint

Updated 2026-10-04 16:28 Asia/Saigon. Repo, raw reports and hashes are authoritative. Preserve valid changes and immutable evidence; no reset/revert.

## Goal and binding rules

Full graph and autoregressive selection on RTL. CPU loads weights/config/prompt and tokenizer/decode only. Pretrained application/reference inference requires exact-current all-seven tests PASS AND full-top post-fit >=100 MHz, all four corners setup/hold/recovery/removal/pulse slack>=0, TNS=0, UCP=0. No timing exceptions to mask failures; FPGA demo is not ASIC signoff.

[AGENTS.md](AGENTS.md): explicit RTL/generate replication; no synthesizable task, variable/unbounded loop or hidden sequential ownership; functions only small pure combinational helpers. Only vendor IP allowed is altsyncram behind the SRAM adapter. No compute/control/DSP/PLL/arithmetic IP or runtime multiply/divide operators.

## Current verified milestone

- main: pushed milestone `3c8ab8e` (fanout candidate A&S PASS); `1b87ed9` helper cleanup and `d72a7cf` current all-seven PASS + release1 FAIL retained. No trained application or CPU checkpoint inference has run.
- Preceding verified snapshot: 33 RTL assets. Unused legacy controllers/helpers removed with stale QSF/source-guide entries; valid legacy tests retained. All 61 request/math/write task calls are visible FSM assignments; generated pipelines have one register owner. LUTs are combinational modules. Unsigned buffer/row casts preserve the former task argument contract. No added numeric/transaction latency.
- [All seven preceding groups PASS](tests/full_rtl/evidence/explicit3_all_units/results.json), completed 14:30:22: Questa2025.2 + official Quartus25.1 RAM; compile/runtime 0 warnings. Graph: prompt2, RTL-selected tokens3, layer executions16, causal checks, 4,229,462 compute clocks, 196,619 host commands. Synthetic fixture, not trained text. Archive has seven logs/binding reports, start/source/test/helper/model hashes and reproduction inputs. Six-group partial tag retained unchanged.
- [A&S PASS](docs/verification/synthesis/explicit2/manifest.json): current 33 RTL + 3 config files, 0 errors/12 warnings, completed13:37:42. This is not timing PASS.
- [Legacy ten groups PASS](tests/evidence/explicit2_legacy_units/results.json), 13:17:30, 0 runtime warnings. Archive is the pre-address-fix snapshot; the later llm_soc-only fix does not affect reachable legacy RTL.
- [Docs validation](docs/source_guide/validation.json): 34 assets/30 main diagrams/15 detail diagrams/150 groups/4523 RTL lines/1059 LUT lines/51 rendered diagrams/1861 links. Link validation rerun after documentation edits; no diagram source changed.

## Current verified source: 34 assets, timing FAIL

- Added reset_release: two explicit standard FFs, async assertion/two-edge sync release. All llm_soc internal reset consumers use core_rst_n. No IP/clock/exception added.
- SIMD partial/pair/product/reduction/sum payload FFs run continuously from captured operands. Start/busy/done/9-clock response and numeric widths unchanged; no wide valid_q enable.
- [Timing release1](docs/verification/timing/fullrtl100_release1/manifest.json) complete15:55:48, all jobs closed. Exact34RTL+3config hashes verified, ZIP37members. A&S0/12, fit0/4, STA0/2, Fmax91.61MHz FAIL. Slow85 setup-.916/TNS-3.387, hold-.023/-.029; slow0 setup-.400/-.629; other17checks PASS/UCP0. Recovery/removal now PASS every corner. Resources51900ALM/48234FF/1186RAM/9515648bits/186pins, DSP/PLL/DLL/HSSI0. SDC unchanged; no trained application.
- All-seven regression pipeline3 PASS, exec63509, work pipeline3_questa_work, official Questa2025.2/RAM25.1. Compile0errors0warnings; all six groups PASS, operators17/checks3460/scalar128/clamp128 completed14:58:02, graph PASS15:46:47, compute clocks4229462/prompt2/tokens3/layer executions16/causal checked/hostcommands196619,0runtimewarnings; graph session closed. [All-seven archive](tests/full_rtl/evidence/pipeline3_all_units/results.json). Eight test inputs and helper/model/log hashes match archived evidence. Initial snapshot tests/full_rtl/build/pipeline3_modelsim_start.json.
- Pipeline1 failed elaboration: mechanical reset rename changed seven child port names. Archived pipeline1_port_binding_failed, fixed .rst_n(core_rst_n). Pipeline2 operator fixture FAIL: seeded token before the new release edges reset it to0. Archived pipeline2_reset_fixture_failed; fixture now releases reset fully before deposits/seeding. Same expected values and exact arithmetic latency checks. All17operators and graph PASS confirm fixture fix.
- [Helper cleanup](docs/history/helper_cleanup1/manifest.json): removed retired native Verilator runner/old evidence merger after caller audit; original two files retained byte-exact in SHA-verified ZIP. Current Questa runners, eight unit inputs, memory helper and all immutable test/timing evidence unchanged. LUT generator retained.
- [Inactive Quartus DB cleanup](docs/history/quartus_database_cleanup_20261004.json):12db/incremental_db directories removed,1864217551bytes freed. All six original source ZIP/report/command hashes verified first; output_files/evidence retained. Active fanout1 DB/model/weights untouched. Historical builds recreate their DB from archived sources/config under a new tag.
- [Additional host-only cancellation probe](tests/full_rtl/evidence/host_cancel_gap1/results.json) PASS7phases/14checks/0warnings,16:26:17, actual RAM IP. Following write after one idle edge ACKs after its own leaf commit. Pre-execution abort prevents write; accepted write may commit despite response cancellation. Earlier two-idle-edge PASS and initial wrong-file-list command failure retained. No RTL/eight unit-input changes or trained graph execution. Numeric-width bounds added to full-graph documentation.

## Complete preceding timing gate: FAIL

[fullrtl100_explicit2](docs/verification/timing/fullrtl100_explicit2/manifest.json) completed14:44:42; its jobs are closed. Exact 33 RTL + three config files verified against initial snapshot and all-seven unit archive. Source ZIP36 members/report/command hashes verified. Map0errors12warnings/fit0errors4warnings/STA0errors2timing warnings. Fmax93.28MHz; slow85 setup-.720/TNS-29.655, removal-.136/-4.137; slow0 setup-.234/-2.973, removal-.149/-5.290. Other16checks PASS/UCP0. 52189ALM/48316FF/1186RAMblocks/9515648bits/186pins, DSP/PLL/DLL/HSSI0. Application gate explicitly rejected Fmax below100MHz; no application ran.

Quartus Lite25.1std.0 Build1129; CycloneV5CGXFC9E6F35C7, seed1/SPEED/STANDARD. SDC10ns/input0.5..2ns/outputsetup2ns/hold0.5ns, no exceptions; LF SHA aa4dc1a48cfd2aabd01770a0eb010b14a2abdfe2cfc9d69968a89b1172ccd181. QSF cache MAX_FANOUT2/op MAX_FANOUT16, physical duplication/high-fanout delay enabled; four unsupported input delay assignments removed. Ordinary clock/reset/SDR LVDS pins, no PLL/SERDES. Board pinout/termination not verified.

## Facts, failures and hypotheses

- [Timing hub](docs/verification/timing/README.md): logic5/6 both FAIL99.07MHz; logic7 FAIL96.04MHz. Setup/hold/removal failures, UCP0, DSP/PLL/DLL/HSSI0. All source/config/raw report tags retained. Logic7 source_hashes_verified=false after unused-source deletion; historical evidence only.
- Current measured setup: write_vector_addr_q[2] -> vector group5 address,10.624ns data/10.285ns routing/one logic level. Other negative paths cache write_pending[0]->lane enables, vector read address->groups, scalar_group->write_vector. Hold fails host_wdata21/19->host_data_q. Reset release and SIMD enable fixes are verified; do not redo them. Next candidate: physical fanout limits on measured address/cache/scalar drivers, unchanged RTL/SDC. Optimize Hold Timing already All Paths. Closure remains a hypothesis until new full fit.
- Explicit1 compile failure and cancelled timing, explicit2 signed-address operator failure, legacy ROM-format/test-interface failures are archived. Fixes preserve expected numeric values; preceding seven groups PASS.
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

Optional -O5 SIMD profile initially refused the active-session license; retry after graph completion PASS503/9reset/513LUT/1536bit checks,0warnings,29s versus default28s. No speed gain demonstrated; default optimizer unchanged. Application early-token observer compile-only PASS, no trained export/run. Pinned model metadata SHA verified; seed0 is a training replica and not yet tested.

## Next priorities

Physical candidate `fullrtl100_fanout1` RUNNING, exec87573, supervisor11928, isolated `quartus_fanout1/llm_soc`. Adds MAX_FANOUT2 vector read/write address, MAX_FANOUT4 cache write-pending/scalar group drivers. RTL34 and SDC unchanged; current all-seven PASS still matches. [A&S archive](docs/verification/synthesis/fanout1/manifest.json) PASS0errors12warnings16:10:22, elapsed6m19. Quartus mapped vector/cache fanout assignments; Fitter active. Snapshot/ZIP37members retained. Do not edit RTL/QSF/SDC or launch another build while runner is active. Hypothesis only; host hold and all20checks need fresh fitting. All release1 jobs closed before launch.

1. Preserve verified release1 FAIL and pipeline3 all-seven PASS, commit/push milestone. Run fresh fanout physical candidate after closed-job check; unchanged RTL can reuse current seven-group PASS.
2. If FAIL, fix measured paths with portable RTL and rerun affected tests/full gates under fresh tags. Never infer timing PASS from synthesis PASS.
3. Validate current docs links/excerpts/render, archive and commit/push verified milestones. No large build artifacts/model/vendor libraries/secrets.
4. After gates: pinned NanoFable actual RTL generation, numeric/token comparison and decoded paragraph quality review; second compatible model when supported and hardware gates pass.
