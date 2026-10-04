# NPU resume checkpoint

Updated 2026-10-04 (Asia/Saigon). Repo, raw reports and byte hashes are authoritative. Preserve valid changes and immutable tags; no reset/revert.

## Goal / binding rules

Full graph/token selection/autoregressive loop on RTL. Host loads weights/config/prompt and tokenizer/decode only. Pretrained application/reference inference requires exact-current full-top post-fit >=100MHz, all four corners setup/hold/recovery/removal/pulse slack>=0/TNS0/UCP0 AND all seven unit/graph groups PASS. No false/multicycle masking. Quartus demo is not ASIC signoff.

Only explicit vendor IP: altsyncram SRAM behind replaceable adapter. No vendor compute/control/DSP/MAC/divider/sqrt/FIFO/PLL/shift-register/FP/Qsys/arithmetic IP or runtime multiply/divide operators. [AGENTS.md](AGENTS.md) binds new explicit RTL rules: generate replication, no synthesizable tasks or variable/unbounded loops; small pure combinational functions only. FSM/handshake/memory/pipeline/register ownership must be visible.

## Current source and jobs

- main, last pushed HEAD e75166e819c1a3f8cf71f85d72a1f2e3e06ef295. Earlier5e621c4/d3825b2 milestones retained. Current edits/evidence NOT yet committed. No pretrained application/reference run.
- Current33assets: unused ctrl_unit/hazard_detect were already deleted on resume, neither top instantiates them. Keep deletions/remove stale legacy QSF/guide entries. Earlier7unused/helper cleanup/consolidation retained; valid legacy tests remain.
- Explicit refactor: all61request/math/write task calls inline in FSM. Explicit unsigned3-bit buffer/4-bit row casts preserve old task argument widths/sign extension. SIMD lane/partial/reduction and parameter valid/owner/address stages use generate; decode/debug/shift/threshold/RAM mux structure visible. Three LUTs are combinational modules, no new latency/numeric values. No synthesizable task/while. Remaining local procedural loops have literal2/4/8bounds; multiplier geometry has staticROWSbound. Package functions are pure numeric/range helpers.
- **Timing fullrtl100_explicit2 RUNNING**, exec58640, isolated quartus_explicit2/llm_soc. Started13:22;33RTL/QSF/QPF/SDC locked and snapshotted before compile. A&S PASS0errors/12warnings at13:37:42; FitterPID20468 active, STA pending. **Do not edit RTL/config or launch another build while active.** Canonical QSF equals isolated config. Device5CGXFC9E6F35C7/seed1/SPEED/STANDARD, Quartus25.1. SDC10ns/input0.5..2/outputsetup2/hold0.5;LF SHAaa4dc1a48cfd2aabd01770a0eb010b14a2abdfe2cfc9d69968a89b1172ccd181. QSF cacheMAXFANOUT2/opMAXFANOUT16 targets measured control path; ignored4inputdelaychain settings removed. Ordinary clockAC18/resetV28/parallel SDR LVDS outputs; noALTLVDS/SERDES/PLL. No board pinout/termination proof.
- **All-seven Questa regression explicit3 RUNNING**, exec65070, work explicit3_questa_work, official25.1RAM build/questa25_model. CompilePASS0errors/0warnings at13:21:25; all6groupsPASS0warnings, operators17/checks3460/scalar128/clamp128 at13:32:57; graph nowRUNNING PID16924. Six-group evidence tests/full_rtl/evidence/explicit3_six_units/results.json and synthesis docs/verification/synthesis/explicit2/manifest.json archived. Initial RTL/test/helper hashes tests/full_rtl/build/explicit3_modelsim_start.json. **Do not edit run_units.ps1, its8testinputs/memory_model.py or work library while active.** Graph5Mcompute/100ms watchdog,196619hostcommands/two-tokenprefill/threeRTLselectedtokens/causal checks unchanged. No relaxed expected values.
- Legacy All regression completedPASS at13:17:30, exec67449:10groups,host168/protocol30/cancel11/blocked4/quantselector4220;numeric/memorycases retained,0runtimewarnings. It used explicit2 preaddressfix33asset snapshot. The later address fix changes only llm_soc, which legacy top does not instantiate; legacy reachable RTL remains identical. Archived tests/evidence/explicit2_legacy_units/results.json with originalsource/test/log SHA and sourceZIP. ROM verifier checks exact new module syntax with same257samples/missing+corrupt rejection; QUANT test drives structural quant_den/reads quant_r_sel with unchanged independentU128expected.

## Verified historical evidence / failures

- [logic6q5 all seven](tests/full_rtl/evidence/logic6q5_all_units/results.json) PASS for original35asset snapshot, QuestaAlteraStarter2025.2 + actualQuartus25.1RAM. Compile/runtime0warnings. RAM158/math503+513+1536/RAM28/protocol29cancel12/selection14/operators17checks3460scalar128clamp128. GraphPASS10:28:31:prompt2/tokens3/layers16/causalchecked/4229462computeclocks/196619hostcommands. Syntheticverification, nottrainedtext.7logs+7optimizerRAMbindingreports/helper/test/start/modelmetadataSHA archived. Changed33sources require freshgates.
- [logic5](docs/verification/timing/fullrtl100_logic5/manifest.json) and [logic6](docs/verification/timing/fullrtl100_logic6/manifest.json) COMPLETE, same35RTL; bothFAIL99.07MHz and identical20slack/TNS/resources. A&S0errors12warnings/fit0errors4warnings/STA0errors2warnings.51986ALM/46834FF/1186M10K/9515648bits/186pins/DSP-PLL-DLL-HSSI0. Slow85setup-.094/TNS-.094,hold-.069/-.171,removal-.138/-4.452;Slow0removal-.166/-5.485. OtherchecksPASS/UCP0. Automaticphysicaloptionsdidnotimproveclosure. Exactsource/configZIPs/rawreportSHA retained.
- [logic7 historical](docs/verification/timing/fullrtl100_logic7/manifest.json) COMPLETE96.04MHzFAIL. Worstsetupop88->lane_round11,data10.141ns/skew-.171;Slow85setup-.412/TNS-3.286,hold-.036/-.069,removal-.139/-4.434;Slow0setup-.024/-.056,removal-.166/-5.479. OtherchecksPASS/UCP0. Fitter171167/ignoredpanel rejectedall4manualinputdelaychain assignments. MapcacheMAXFANOUT2insertedlogiccells;fit5registerduplicates. Runner rejectedfinalsource-set mismatch after2unusedlegacyfiles deleted; original35sources recoveredbyteexactfromlogic6ZIP. Manifest source_hashes_verified=false for workspace comparison; cannotgatecurrentcode.
- Actualremaining paths: onehotcontrolfanout,hostinputhold,rawresetremoval into packedoutputFFs. Earliercache9.188ns/0comb/fanout8offworstpathinlogic7. Reset/outputFFstructuremayneedportablefixwith explicitcontract/freshgates aftercurrentresults; noassumedtimingfix.
- explicit1compileFAIL9errors: inlineparser splitconcatenationcommas, LUTnetdeclaredafteruse. Archived tests/full_rtl/evidence/explicit1_compile_failed. Fixedbracket-awareparser/netorder; explicit2compile0warnings.
- explicit2operatorFAIL at13:14:30:attentionaddr60expected-12/actualX. Diagnostic shows correctexp/probability/accumulation; addresscasts signedliteralbuffer5 becomes-3, wrongwriteaddr. Repaired with explicit$unsigned for oldtaskunsigned3/4-bitports. Numericexpectedunchanged. Rawlogs/source/test snapshot retained tests/full_rtl/evidence/explicit2_operator_failed. Freshexplicit3regressionrequired.
- Timing [fullrtl100_explicit1 cancellation](docs/verification/timing/fullrtl100_explicit1/cancellation.json): knownoperatorFAIL, stoppedonlyownedsupervisor12664/map3036 afterCIMverification, beforefitting.33source+3configZIParchived beforefix. NoA&S/timingPASSclaim.
- LegacyROMformatFAIL and unresolvedoldchoose_quant_r testinterfaceFAIL archived tests/evidence/explicit1_rom_format_failed and explicit2_selector_interface_failed; onlysyntax/testconnectionupdated, sameexpectedcases. RerunAllPASS above.
- OldQuesta namespace/singlewriter/width failures and cancelledModelSimgraph preserved under tests/full_rtl/evidence/logic6*failed / logic6_modelsim_cancelled. Fixture seedsRAMvia leafwriteports; scalarcontrolsdeposit/force-release, noerrorsuppression. Old35source six/legacyPASSnotcurrentfullgates.
- [RAM25](docs/verification/memory_ip/ram25/results.json) ModelSimPASS158/protocol29cancel12/selection14/0warnings, official25.1source. Archiveincludesoriginalhelperv1; vendorcode/libraryobjects notcommitted.

## Tools / docs / reproduction

Quartus C:/altera_lite/25.1std/quartus/bin64 (Lite25.1std.0Build1129). Questa C:/altera_lite/25.1std/questa_fse/win64 (Starter2025.2). ModelSim C:/intelFPGA/20.1/modelsim_ase/win32aloem. Old18.1exeabsent. Nativeunsignedhelpers blockedWindowsApplicationControl4551; do notbypass/substitutefakeRAM.
Python C:/Users/khanh/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe; Node siblingnode/bin/node.exe; Edge headless DOCS_BROWSER_PATH.

docs/README.md hub, docs/design/rtl_style.md and sourceguide33assets refreshed; validationPASS33assets/29mainRTLdiagrams/147groups/4504RTLlines/1059LUTlines/50renderedMermaid/1829links at13:36,refreshafterfinaldocedits. Two obsoleteguidepagesremoved. Apphelpers gate exactsource/config/report/input/runner/model/units/freshlogs; QuestaRAMproof uses optimizerDUreports, ModelSimexplicitLoadinglibrary. No application/referencecheckpoint inference has run. Numeric/tokenmatch separate from meaning/coherence of actualRTLdecodedparagraph.

```powershell
Get-CimInstance Win32_Process | Where-Object { $_.Name -match 'quartus|vsimk' } | Select ProcessId,ParentProcessId,Name,CommandLine
Get-Content docs/verification/timing/fullrtl100_explicit2/map.log -Tail 12
Get-Content tests/full_rtl/build/tb_llm_operators.log -Tail 8
Get-Content tests/full_rtl/build/tb_llm_graph.log -Tail 8
# Reproduce after activejobs finish; freshwork/tag/database only:
./tests/full_rtl/run_units.ps1 -SimBin C:/altera_lite/25.1std/questa_fse/win64 -Questa -MemoryModelManifest tests/full_rtl/build/questa25_model/manifest.json -TimingManifest docs/verification/timing/fullrtl100_logic5/manifest.json -WorkLibraryName NEW_WORK -EvidenceTag NEW_UNUSED_TAG
./tests/run.ps1 -Block All -SimBin C:/intelFPGA/20.1/modelsim_ase/win32aloem
./tools/timing/run.ps1 -Project quartus_explicit2/llm_soc -Tag NEW_UNUSED_TAG -QuartusBin C:/altera_lite/25.1std/quartus/bin64 -Python C:/Users/khanh/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe
python docs/source_guide/validate.py
# ONLY exact-current hardware AND allsevenPASS:
./tests/full_rtl/run_application.ps1 -TimingManifest docs/verification/timing/PASS_TAG/manifest.json
```

## Next priorities

1. Finishexplicit3regression/explicit2map+fit+STA/allcorners. Verifyhash/RAMbinding/warnings/resources/criticalpaths; archivebeforeedits. No synthesisPASS=>timingPASS inference.
2. Fixmeasuredremainingpaths/resetrelease withportableRTL/newimmutabletag/revalidategates; do notduplicatebuilds/editlockedsources.
3. Complete/read docsexplanations/link/excerpt/render validation. Refreshcheckpoint; verify stagedbytes/evidence, commit/push verifiedmilestonehonestly; no weights/checkpoints/vendorlibraries/buildDB/secrets.
4. Aftergates run pinnedNanoFableRTLapplication, numeric/tokencompare and actualdecodedparagraphreview; secondcompatiblemodel conditionalhardware/support. Nohostintermediate/logits/nexttoken injection.
