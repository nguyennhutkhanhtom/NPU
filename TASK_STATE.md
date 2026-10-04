# NPU resume checkpoint

Updated 2026-10-04 (Asia/Saigon). Repo, reports and byte hashes are authoritative.

## Goal / rules
Full token graph and autoregressive loop on RTL; host only loads weights/config/prompt and tokenizer/decode. Exact-current full-top post-fit >=100MHz. All four corners: setup/hold/recovery/removal/pulse slack>=0, TNS0, unconstrained0. No false/multicycle masking. All seven unit/graph groups PASS before any pretrained application/reference inference. FPGA demo is not ASIC signoff.
Only explicit vendor IP is altsyncram SRAM behind the replaceable memory adapter. Compute/control uses standard cells and synthesizable SV only. No multiply/divide operators for datapaths, DSP/MAC/divider/sqrt/FIFO/PLL/shift-register/FP/Qsys/arithmetic IP. Constant elaboration geometry is not a runtime multiplier/divider.

## Current work and jobs
- main HEAD5e621c4 pushed: archived control1 arithmetic/control and six-unit verification, honest92.75MHz timingFAIL. Earlierd3825b2/cleanup milestones remain pushed. Preserve valid edits and immutable tags, no reset/revert.
- New logic_mul.sv: sign/zero-extended AND/shift bit rows, signed B top-row complement plus one, 3-to-2 XOR/majority compressors, one final ordinary adder. Exact low OUT_W modular product; independent signedness. No multiply/divide operator/IP, no reset/handshake inside this combinational cell. All full and legacy datapath multiplication sites now use it; existing product FFs/RNE/clamps/latencies preserved.
- Runtime constant power-of-two address/word-count calculations now use explicit shifts; full-top buffer*12 and layer*7 use shift/add or shift/subtract. Divider/sqrt already use shift/subtract, unchanged. SIMD done9/reset9; scalar partial/pair/sum stays3edges. 102 onehot states unchanged.
- Parameter address payload selects by registered compute rd_en under mutually exclusive host/core reads; raw host cancellation stays in enables/valid/address tags. SRAM latencies/collisions/reset contract unchanged.
- Seven deleted standalone legacy/helpers preserved: addsub, de_reg, em_reg, exp, fd_reg, mem_burst, mw_reg. addsub is still needed by arithmetic tests, so its ordinary S17 add/sub/saturation module was consolidated into mul.sv; testcase retained. Removed stale QSF assignments and seven obsolete source-guide pages. Current35source assets.
- QSF full and legacy disable DSP and automatic shift-register recognition. Full QSF uses ordinary2.5V clockAC18/resetV28, packed parallel SDR LVDS output buffers with negative companions. No ALTLVDS/PLL/SERDES. External host must receive differential output bus; board termination/pinout not supplied. SDC10ns and I/O budgets unchanged; canonicalLF SHAaa4dc1a48cfd2aabd01770a0eb010b14a2abdfe2cfc9d69968a89b1172ccd181.
- Current timing job fullrtl100_logic5, exec24763: A&S PASS0errors/12warnings; Fitter advanced physical placement optimization active, then STA/extraction, Quartus Lite25.1std.0 Build1129. Fresh isolated project quartus_logic5/llm_soc has QSF/QPF/SDC byte-identical to canonical quartus/llm_soc and points to same35RTL assets. Separate database avoids orphan/duplicate writes. No100MHz result claimed yet. Never edit source/config while it runs.
- Completed six-unit job logic4, exec65390: actual Intel memory158, math503/reset9/LUT513/bit1536, RAM28, protocol29/cancel12, selection14 already PASS; operators17/checks3460/scalar128/clamp128 PASS, ended08:23:19 after19m48s/643335clocks. All six runtime0warnings, archived tests/full_rtl/evidence/logic4_six_units/results.json. Compile0errors/8reviewed SVCHK deferred-vopt notices. Initial snapshot tests/full_rtl/build/logic4_modelsim_start.json before compile. -UnitsOnly returns SIX_GROUPS_PASS_GRAPH_PENDING, never all-sevenPASS; default still runs graph. Application gate unchanged and still requires all seven.
- Legacy All regression PASS for current35RTL hashes:10groups,168host/30reads/11cancels/4blockedregions,106division/4301sqrt/37189RNE/900compose(max54cycles),5dividerprofiles,12720postscale,1638400sigmoid/25formats,3242addsub/4452mul/5accumulatorprofiles,1800rowwise/13260elements/reset6,1027imem/47SRAM. All runtime0errors/0warnings. Raw logs+SHA archived tests/evidence/logic4_units/results.json. Earlierlogic2/3PASS belongs to old hashes; had3dead-instance width warnings, fixed.

## Failures / facts / hypotheses
- ModelSim accepted implicit generate, but Quartus25.1 rejected it: fullrtl100_logic2/map.log13errors. Fixed explicit genvar and generate/endgenerate; logic3 parsed/synthesized, then cancelled for legacy warning cleanup. logic1 ModelSim compile failed2errors from instance before operand declarations; fixed. Keep failure/cancellation logs/source hashes, no PASS claim.
- Replacement script accidentally added unused logic_mul to postscale_finish with implicit1bit nets. Removed; default_nettype none/wire now protects this file. Legacy regression proves width warnings gone; no expected values changed.
- logic3 fitter child started just before supervisor cancellation. Detected and stopped owned fitter plus logic4map/helper, then launched fresh isolated logic5. logic4 cancellation record notes database interference risk; neither tag is current acceptance.
- Previous fulltop control1:92.75MHz FAIL setup/hold/recovery,31573ALM/42133FF/1187M10K/9519744bits/128pins/DSP-PLL-DLL-HSSI0. Slow85setup-.769/TNS-28.611,hold-.152/-.499,recovery-1.288/-7.565;Slow0setup-.782/-26.071,recovery-.910/-5.311. Fast setup3.094/3.417,hold.128/.046;removal/pulsePASS,unconstrained0. Six unitsPASS, graph cancelled for measured host mux fix. Full archives/zips/source hashes are in docs/verification/timing/fullrtl100_control1, committed.
- Measured old host_en->parameter addressFF13.158ns motivates rd_en mux ownership fix. LVDS clock receiver.907ns vs earlier2.5V.917ns did not help; old outputclock6.048+data2.634 missed7.9ns requirement. ResetW27 non-dedicatedGCLK15 route caused14ns resetdata/recoveryFAIL; currentresetV28 is a known dedicated input candidate. Still a hypothesis until new fit.
- Eight-FF ordinary LVDS output probe on C7/Quartus18.1: four corners setup+.422/+.380/+3.951/+4.088,hold+.692/+2.701/+1.936/+.631,pulsepositive/TNS0/UCP0. Recovery/removal NA(noreset). Fitted0DSP/PLL/DLL/HSSI. This is I/O characterization only, not fullgraph100MHz.51rawreports/source/config/helperSHA archived docs/verification/io_cells/lvds_output18/manifest.json; no build databases committed.
- Earlier fulltags bytes1=89.60,memoryip2=87.49,tiled70.41,pipeline2=83.58,local1=84.49,tree2=91.28,select3=92.22,group2=81.53 allFAIL. Earlier102DSP tags cannot gate current policy; legacy49.49 is not llm_soc.
- Only installed Quartus executable now C:/altera_lite/25.1std/quartus/bin64. Old18.1 executable absent. Simulation still ModelSimIntelStarter20.1/-L altera_mf_ver; its real20.1RAM model vs hardware25.1 difference must be stated.158contract checks cover4geometries,OLD_DATA/read3or4/write2/queuedwritecancel/retention without IP internal seeding.

## Documentation / tools
- docs/README.md hub links architecture/fullgraph/memory/ASIC portability/source guide/tests/timing. Current35assets,31mainRTLdiagrams,150groups/4524RTLlines/1044LUTentries.52Mermaid renderPASS; links/excerpts/hash validator PASS (refresh after final text/hash edits). New logic_mul diagram rendered; visual inspection PASS. Old architecture width tables explicitly historical.
- Python C:/Users/khanh/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe; Node sibling node/bin/node.exe. Quartus25.1 above; ModelSim C:/intelFPGA/20.1/modelsim_ase/win32aloem. Edge headless renderer uses DOCS_BROWSER_PATH.
- Native unsigned binaries blocked Windows Application Control4551; do not bypass or silently replace actual memory IP with USE0 for graph/application. Operator fixture USE0 solely for numeric internal initialization; actual IP/protocol/selection/graph/application USE1.
- No trained application/reference inference run. Export/finalizer gate exact source/config/report/test/input/runner SHA and fresh logs; token matching PASS is distinct from text quality/meaningful paragraph. All7 graph gate remains mandatory.

## Reproduce / priority next steps
```powershell
Get-Process quartus_map,quartus_fit,quartus_sta,vsimk -ErrorAction SilentlyContinue
Get-Content docs/verification/timing/fullrtl100_logic5/map.log -Tail 12
Get-Content tests/full_rtl/build/tb_llm_operators.log -Tail 8
# Do not duplicate while current jobs run:
./tests/full_rtl/run_units.ps1 -UnitsOnly -EvidenceTag NEW_UNUSED_TAG
# Isolated config must remain byte-identical; create new sibling folder for retry.
./tools/timing/run.ps1 -Project quartus_logic5/llm_soc -Tag NEW_UNUSED_TAG -QuartusBin C:/altera_lite/25.1std/quartus/bin64 -Python C:/Users/khanh/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe
# After hardware gates PASS, run actual-IP graph using unchanged compiled work.
# Merge all seven only after real graph PASS with the same initial source/test hashes:
python tools/llm/merge_unit_evidence.py --start tests/full_rtl/build/logic4_modelsim_start.json --modelsim-graph tests/full_rtl/build/tb_llm_graph.log --output tests/full_rtl/evidence/NEW_UNUSED_UNITS
# Only after exact-current hardware + all-seven-unit gates:
./tests/full_rtl/run_application.ps1 -TimingManifest docs/verification/timing/PASS_TAG/manifest.json
```
1. Finish logic5 fitting/allcorners; six logic4unit groups completedPASS. Inspect actual LVDS companion pins/reset routing, resources, warnings and critical paths. Preserve source/config/report hashes. If FAIL, fix measured path and use new immutable tag/revalidate; do not call A&S PASS timing PASS.
2. After hardwarePASS run actual-IP fullgraph; preserve196619hostcommands/two-tokenprefill/threeRTLselectedtokens/causal checks. Default graph watchdog5Mcompute/100ms covers existing9edgeSIMD. No relaxed expected values or dropped cases.
3. Refresh/inspect docs/diagrams and checkpoint, verify staged byte hashes, commit/push verified milestone honestly. Exclude weights/checkpoints/large database/cache/secrets; raw evidence EOL filters disabled.
4. After allgates run pinned NanoFable application, independently compare numeric/tokens, evaluate actual RTL decoded paragraph; second compatible model conditional hardware/support. Never feed host intermediates/logits/nexttoken to RTL.
