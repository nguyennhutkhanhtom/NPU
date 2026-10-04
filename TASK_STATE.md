# NPU resume checkpoint

Updated 2026-10-04 20:04 Asia/Saigon. Repo/reports/hashes are authoritative; preserve valid changes and immutable tags, no reset/revert.

## Goal and rules

Full autonomous language graph on RTL; CPU loads weights/config/prompt and tokenizer/decode only. Quartus is the EDA synthesis/timing demo backend. Focus ASIC-portable RTL and replaceable SRAM technology binding; no FPGA board/peripheral bring-up. Quartus timing is not ASIC signoff.

[AGENTS.md](AGENTS.md): explicit RTL/generate, obvious ownership; no synthesizable task, variable/unbounded loops or hidden significant datapaths in functions. Only SRAM leaf altsyncram vendor IP; no compute/control/arithmetic/DSP/PLL IP or runtime multiplication/division. Keep constraints/test expectations strict.

Pretrained export/application/reference inference requires exact-current all-seven unit/graph PASS AND full-top post-fit>=100MHz, every corner setup/hold/recovery/removal/pulse slack>=0,TNS0,UCP0. No trained application/reference inference has run under this gate.

## Current attention1 fix: gates pending

Source llm_soc changes one clear assignment: A_QUERY clears attention_acc_q instead of conditional clear in A_EXP_STORE. No state/cycle/numeric formula changed. Each head enters A_QUERY before scores; accumulators only consumed after exponent generation. No vendor IP/task/function/loop added. QSF adds host_addr D3_DELAY7 for fanout2 address hold failures; SDC unchanged.

RUNNING timing exec49792, isolated quartus_attention1/llm_soc, tag fullrtl100_attention1; A&S PASS0errors12warnings19:41:12, Fitter45332/supervisor30228 active. Source/config ZIP37 SHA0f9badde7a854d76f1edb6541af9f1547d132579c39342d94a14968dd43c059e. RUNNING all-seven exec25145, attention1_questa_work/EvidenceTag attention1, actualRAM25.1/Questa2025.2; initial snapshot tests/full_rtl/build/attention1_modelsim_start.json, compile0errors0warnings, allsixgroupsPASS including operators17/checks3460/scalar128/clamp128 at19:39:11; graph40192 RUNNING. Six-group archive tests/full_rtl/evidence/attention1_six_units/results.json, A&S archive docs/verification/synthesis/attention1/manifest.json. Rootunit_results currently RUNNING, not PASS. Preserve prior pipeline3 archive; no application.

Source guide refreshed/excerpts/hash match34assets;51diagram hashes unchanged. Do not edit RTL/QSF/SDC or unit inputs while jobs active. Wait for current graph and full fit/all20checks before claiming milestone. Latest pushed a2fa161 records early attention clear/A&S/six units; c9a83b9 completed fanout2 FAIL and bc4f375 vendor-free elaboration/ASIC memory guide retained.

Current source policy review docs/verification/rtl_policy_attention1/results.json: exact34hashes,41generate/13small static procedural/2elaboration loops,13pure runtime helpers/2geometry functions. All61arithmetic-symbol statements reviewed as elaboration/index geometry, vendor symbols SRAM leaf only. Manual review plus lexical inventory, not a functional/timing proof. Docs hub simplified; validator PASS34assets/51renders/1901links. Graph passed1Mcompute clocks by20:03; still RUNNING.

## Preceding verified RTL and tests

- 34RTL/source assets: explicit inline FSM requests, generated LUT/pipelines, structural bit-product arithmetic. SRAM only behind adapter; reset conditioner two standard FFs, async assertion/two-edge release. SIMD payload stages continuous from captured operands, nine-clock response unchanged. Do not redo verified fixes.
- [Seven groups pipeline3 PASS](tests/full_rtl/evidence/pipeline3_all_units/results.json), Questa2025.2 + official Quartus25.1RAM,0compile/runtimewarnings. Math503/reset9/LUT513/bit1536; operators17/checks3460; graph4229462compute clocks/prompt2/selected tokens3/layerexec16/hostcommands196619/causal checked. Synthetic fixture, not trained text. This preceding34RTL snapshot/eight test inputs/helper/logs/binding hashes match its archive; current clear-attention source is different.
- [Optional host cancellation](tests/full_rtl/evidence/host_cancel_gap1/results.json) PASS7phases/14storagechecks with one idle edge between requests. Accepted write may commit after response cancellation; no rollback promise. Following request ACK follows its own commit. No RTL/test-input changes.
- [Docs](docs/source_guide/validation.json) PASS34assets/30main+15detail diagrams/150groups/4523RTLlines/1059LUTentries/51rendered/1896links. Current Mermaid hashes match rendered evidence.

## Latest full-top timing: fanout2 FAIL96.67MHz

[Manifest](docs/verification/timing/fullrtl100_fanout2/manifest.json), [ZIP](docs/verification/timing/fullrtl100_fanout2/source_archive.json), completed19:29:55. All Quartus jobs closed; exec33458 complete. Exact34RTL/3config/37ZIP/currentsevenunits/allreport-command hashes verified. Map0errors12warnings/fit0errors4warnings/STA0errors2timingwarnings. Resources51888ALM/48214FF/1186RAM/9515648bits/186pins; DSP/PLL/DLL/HSSI0. UCP0;17/20checks PASS. Slow85 setup-.345/TNS-62.291,hold-.093/-.153; slow0 setup-.116/-.834. Other17checks nonnegative/TNS0, including recovery/removal/pulse every corner. SDC unchanged. No pretrained application.

Physical host_wdata D3 setting7 applied to all32bits; their hold now PASS. Hold fails host_addr20/11/15 (.093/.042/.018ns), stillD3 setting6. Setup now position_q[2]->attention_acc_q[16],10.070nsdata/8.246nsrouting/fourlevels; equality/clear cone controls32S56accumulators. Quartus recommends position/equality duplication. Portable next fix: clear accumulators at A_QUERY, each attention head entry before scores, removing late time_q==position_q condition from wide clear. No extra state/cycle needed; must rerun all-seven and full timing for changed RTL. Do not redo verified reset/SIMD fixes.

## Preceding timing: fanout1 FAIL98.63MHz

[Manifest](docs/verification/timing/fullrtl100_fanout1/manifest.json), [ZIP](docs/verification/timing/fullrtl100_fanout1/source_archive.json), [timing hub](docs/verification/timing/README.md). Completed17:28:31; all Quartus jobs closed by18:26 process check. Source34/config3/ZIP37/all report-command hashes verified. Source ZIP SHA bcc79c19800d70a1039ffae20f7a3d4c1f3d20fc7766dcc0d1a921da9d9910c0.

Quartus Lite25.1std.0 Build1129, CycloneV5CGXFC9E6F35C7, seed1/SPEED/STANDARD. SDC10ns,inputmin.5max2ns,outputsetup2hold.5ns,no exceptions; LF SHA aa4dc1a48cfd2aabd01770a0eb010b14a2abdfe2cfc9d69968a89b1172ccd181. Ordinary clock/reset/SDR outputs, no PLL. Physical QSF settings are demo-backend bindings, not ASIC architecture.

- A&S0errors12warnings/fit0errors4warnings/STA0errors1warning. Raw STA says singular1warning; old parser recorded null totals. Immutable manifest retained, parser fixed for future tags; three tests against actual reports PASS. Initial parser test decoding error corrected with recorder-equivalent UTF-8 replacement, expected totals unchanged.
- Resources51919ALM/48086FF/1186RAMblocks/9515648bits/186pins; DSP/PLL/DLL/HSSI0. UCP0 every category,18/20checks PASS.
- Slow85 setup-.139/TNS-.268, hold-.102/-.578, recovery2.898/0,removal.936/0,pulse3.600/0. Other15checks PASS: slow0 setup.112,hold.231,recovery2.752,removal1.219,pulse3.543; fast85 3.321/.128/4.537/.642/3.798; fast0 4.032/.115/6.320/.583/3.788, all TNS0.
- Worst setup k_write_address_q[3]->cache request groups7/6,9.858nsdata/9.243nsrouting/zero logic. Nine hold endpoints host_wdata14/13/27/6/24/23, worst3.950nsdata/4.552nscapture clock with.5nsinputmin; fittedD3_1=6. Prior vector/cache-enable/scalar negative paths fixed in this fit. Application gate explicitly rejected Fmax below100MHz.
- Prior release1 FAIL91.61MHz and explicit2 FAIL93.28MHz remain immutable. Legacy49.49MHz is not full-top timing. Reset recovery/removal fixes PASS all corners; no need redo.

## Cleanup and commits

Latest source/six-unit milestone pushed main a2fa161; preceding timing/parser d6e5377 preserved. Prior86b1c52: inactive Quartus DB cleanup12directories/1864217551bytes; all six historical ZIP/report hashes verified, outputs/evidence/activeDB/weights/model cache retained. [Cleanup record](docs/history/quartus_database_cleanup_20261004.json). Prior unused helper originals preserved in [SHA-verified ZIP](docs/history/helper_cleanup1/manifest.json); current runners and legacy reachable modules retained. No large weights/build artifacts/vendor libraries/secrets committed.

## Reproduction and next steps

Tools: Quartus C:/altera_lite/25.1std/quartus/bin64; Questa C:/altera_lite/25.1std/questa_fse/win64; Python C:/Users/khanh/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe. Unsigned native helpers blocked by Windows Application Control; no bypass.

```powershell
Get-CimInstance Win32_Process | Where-Object { $_.Name -match 'quartus|vsimk' } | Select ProcessId,ParentProcessId,Name,CommandLine
python tools/timing/test_record.py -v
python docs/source_guide/validate.py
./tools/timing/run.ps1 -Project quartus_fanout1/llm_soc -Tag FRESH_TAG -QuartusBin C:/altera_lite/25.1std/quartus/bin64
./tests/full_rtl/run_units.ps1 -SimBin C:/altera_lite/25.1std/questa_fse/win64 -Questa -MemoryModelManifest tests/full_rtl/build/questa25_model/manifest.json -WorkLibraryName FRESH_WORK -EvidenceTag FRESH_TAG
# ONLY after exact-current all hardware/unit gates PASS:
./tests/full_rtl/run_application.ps1 -TimingManifest docs/verification/timing/PASS_TAG/manifest.json
```

1. Fanout2 FAIL archived/pushed c9a83b9. Current attention1 timing/unit jobs active: poll logs/processes, keep sources frozen. Archive fresh results without overwriting old tags.
2. Verify current early attention clear numerically with all-seven tests, then all-corner timing. If FAIL target new measured paths. Preserve SDC, expected values and evidence; no pretrained run until exact-current full gates pass.
3. Once gates pass, run pinned NanoFable actual RTL paragraph and review matching separately from coherence; second compatible language model when supported. O5 profile gave no speed gain, defaultO4 retained. Application monitor compile-only PASS, not an application run.

[Portable full-top elaboration](docs/verification/portable_elaboration1/results.json) PASS18:37:16, USE_QUARTUS_MEMORY=0, no vendor library loaded/24module design units/14unique names/0errors0warnings, run0/no weights/inference. Initial shell argument split failure retained; corrected quoting only. [ASIC SRAM binding guide](docs/design/asic_memory_binding.md) records all72leaf instances, latency/reset/collision and four small arrays including inferred output/probability RAM. Behavioral elaboration is not ASIC synthesis or signoff.

Source-guide refresh helper fixed trailing-blank-line boundary drift. Reset FF excerpt ownership preserved; docs/verification/doc_refresh1/results.json records36pages/manifest byte-idempotence PASS. This is a documentation helper fix only.
