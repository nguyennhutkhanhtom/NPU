# NPU resume checkpoint

Updated 2026-10-02 04:32 (Asia/Saigon). Actual repo/reports/hashes override chat.

## Objective / strict gate
Full graph and autoregressive token selection on RTL; CPU loads data/config/prompt and tokenizer/decode only. Exact-current post-fit >=100MHz at all four corners, all setup/hold/recovery/removal/pulse PASS, TNS0, unconstrained0. No false/multicycle masking. Pretrained application has NOT run; it remains gated. FPGA evidence is not ASIC signoff.

## Current checkpoint / user technology policy
- Latest request: FPGA may use Quartus memory IP only; no DSP, PLL or other compute IP. Add/sub/carry and ordinary logic cells allowed. ASIC memory binding will replace FPGA RAM later. No PLL follow-up is authorized.
- main; cleanup305d7b5/12ae49e/96297da pushed. Functional d9ed792 pushed. Preserve current valid edits, immutable timing/source zips and old test evidence; no reset/revert.
- **Current FPGA backend implemented:** llm_soc.USE_QUARTUS_MEMORY=1 (default), propagated through parameter/vector/KV adapters. quartus_word_ram.sv is the sole explicit vendor primitive: altsyncram M10K, one common-clock read + write, rawread1edge, OLD_DATA, storage/output unreset. Seventy-two whole-bank IPs replace352 manually tiled leaves; earlier memory already mapped to M10K, so measured area/load gains need actual report.
- Adapter read3edges for ROWS≤4096,4otherwise; writecommit2; reset cancels queued enables/valid, retains committed storage. llm_bank read5/writecommit4/wr_busy drain; parameterread5at24576 or4≤4096,hostlane+1 and ACKaftercommit. ASIC behavioral backend0 stays available behind same interface; operator numeric fixtures explicitly choose0. Protocol/selection/graph/application use actual FPGA IP1.
- **Memory IP contract PASS:** actual ModelSim Intel20.1 altera_mf_ver vs portable model,4banks (24×96,24×4096,32×3072,32×24576),158checks: boundaries/back-to-back/OLD_DATA/resetallreadphases/queuedwritecancel/retainedword. No runtime warnings.
- **Current six groups PASS:** IP158;math503/reset7/LUT513;RAM28;protocol29/cancel12(actualIP);selection14(actualIP);operators17/checks2820/11m31s,0runtimewarnings. Sequential full graph started04:07, vsim8452/vsimk32952; inspect log/process before edits. Unit aggregate RUNNING, not application gate. Initial exact41RTL/test hashes: build/ip1_modelsim_start.json. Six complete unit logs archived evidence/memoryip_six_units; first partial archive retained. Supervisor execsession9445 waits for runner33324 then merges seven into evidence/memoryip_units. Compile0errors/8SVCHK notices.
- **A&S PASS0errors/13warnings for fullrtl100_memoryip2** at04:05:39; actual map.summary **DSP0/PLL0**,33108registers,9519744memorybits. **Fit0/4,STA0/2 complete**, worst87.49MHz/setupFAIL; fit0DSP/0PLL,29115ALM/34716reg/1187M10K. All hold/recovery/removal/pulse PASS,TNS0 andunconstrained0. Slow85setup−1.430/TNS−157.190,Slow0−1.253/TNS−250.719. Tag archives/report hashes verified; no Quartus process remains. Device5CGXFC9E6F35C7,QuartusLite18.1,SPEED/STANDARD/seed1. Explicit RAM IP, AUTO_DSP_RECOGNITION OFF, DSP_BLOCK_BALANCING LOGIC ELEMENTS; restore FAST_OUTPUT_REGISTER ON. SDC unchanged SHAaa4dc1a48cfd2aabd01770a0eb010b14a2abdfe2cfc9d69968a89b1172ccd181:10ns/allIO/noexceptions. Exact44inputs archived before further changes. Static A&S evidence docs/verification/memory_ip (report/log/snapshot SHA), independent of running fit logs.
- fullrtl100_memoryip1 preserves2error QSF parser rejection for MAX_DSP_BLOCKS unsupported18.1, no synthesis/fit/timingPASS; map.log/failure.json/44assetzip retained. Retry removes only invalid assignment. ZeroDSP/PLL application gate now checks actual fit.summary and its report hash.
- Pre-IP group2fit0/3 but timingFAIL81.53MHz/setup+hold,102DSP; old five groups PASS. Its graph cancelled when memory policy changed; no functional assertion failure. Archive evidence/group2_modelsim_partial/graph_cancelled_for_memory_ip.log and five_pass_graph_cancelled.json. Earlier select3 sixPASS belongs to archived source, not current.
- Windows Application Control4551 blocked native executables; no bypass. compiled_sim.py now rejects all/protocol/selection/graph/application without actual Intel model; use ModelSim -L altera_mf_ver. merge_unit_evidence.py requires all seven groups, exact hashes, actual-IP loading and clean graph. Never silently select memory backend0 for FPGA graph/application.
- Architecture unchanged:96onehotopstates; sigmoidRNE4/S16clamp/8:1then4:1mux; eight separatelyenabled scalarregs/fourlanes each; unconditional host_rdata FF behind transactionpayload. SignedA_SCALE,eligibleS32MINfallback,ternary10fault,finalKVdrain retained. Compute has no synthesis ifdefs/vendorinstances.
- Docs hub/source guide refreshed41assets/37main/158groups/4625RTLlines/1044LUTlines/1804links PASS; all58Mermaid diagrams rendered, newIP/adapter diagrams visually inspected. FPGA/ASICcontract and noDSP/PLL policy documented. No pretrained application run.
- Cleanup pushed:11unusedhelpers60799B;6unusedcaches1289444696B;224stalerenders10393764B. Manifests docs/history/*cleanup_20261002.json; weights/tokenizer/currenttests/evidence retained.

## Verified timing facts
Device `5CGXFC9E6F35C7`,QuartusLite18.1,topllm_soc,SPEED/STANDARD/seed1; clk10ns,input0.5..2ns,outputsetup2/hold0.5ns,derived uncertainty,127realI/O,no exceptions.

| Immutable tag | Result |
|---|---|
| fullrtl100_tiled | A&S0/6,fit0/4; FAIL70.41MHz. Slow0−4.202/TNS−4791.870;Slow85−3.781/−5323.438.1111RAM/24125ALM/104DSP. |
| fullrtl100_pipeline1 | Sandbox QSYN named-pipe map failure; snapshot retained. Outside-sandbox retry auto-approved, no approval rejection. |
| fullrtl100_pipeline2 | A&S0/6,fit0/4; FAIL83.58MHz. Slow85−1.965/−669.972;Slow0−1.518/−258.929.1111RAM/23060ALM/104DSP. |
| fullrtl100_local1 | A&S0/6,fit0/4; FAIL84.49MHz. Slow85−1.836/−952.596;Slow0−1.687/−260.523.1187RAM/22873ALM/102DSP. |
| fullrtl100_tree1 | A&S0/6, fitter explicitly cancelled after final KV write unit failure; source/logs retained, no timing acceptance. |
| fullrtl100_tree2 | A&S0/6,fit0/29; **FAIL91.28MHz**. Slow85−0.847/TNS−158.461;Slow0−0.955/−58.743.24233ALM/34698reg/1220M10K(all)/252MLAB/102DSP. |
| fullrtl100_select1 | QSF parser rejected foreach;3maperrors. Archived exact config/log; fixed with explicit assignments in next tag. |
| fullrtl100_select2 | Processes interrupted during map/native compile/operator test when tool session changed; no acceptance. Exact43assets/log retained. |
| fullrtl100_select3 | A&S0/7,fit0/29; **FAIL92.22MHz**. Slow85−0.844/TNS−16.608;Slow0−0.560/−13.116.25476ALM/35233reg/1220M10K/252MLAB/102DSP. Six units PASS for archived source. |
| fullrtl100_group1 | A&S2errors/0warnings: inlinegenvar in explicit generate region rejected by Quartus18.1. Exact43assets/log retained. Fixed declaration location in group2; four units PASS then operator cancelled, not a functional assertion failure. |
| fullrtl100_memoryip1 | QSF MAX_DSP_BLOCKS unsupported18.1;2errors/0warnings, exact44assetarchive. |
| fullrtl100_memoryip2 | A&S0/13,fit0/4,STA0/2; **FAIL87.49MHz/setup**. Slow85−1.430/TNS−157.190;Slow0−1.253/−250.719.29115ALM/34716reg/1187M10K/0DSP/0PLL; all other checks PASS/unconstrained0. |
| fullrtl100_group2 | Pre-IP immutable snapshot; A&S0/7,fit0/3, **FAIL81.53MHz**. Slow85setup−2.265/TNS−46.475 ANDhold−0.072/TNS−0.175;Slow0setup−2.187/−40.230.26534ALM/39945reg/1187M10K/0MLAB/102DSP. Five ModelSim groups PASS/graph later cancelled for IP change. |

Completed full-top tags: fast setup and recovery/removal/pulse PASS, unconstrained0. Earlier tags also all hold PASS; group2 adds Slow85 input-hold failure. OtherTNS0. STA tool success is not timing PASS. Legacy49.49MHz is not full llm_soc.
Select3 worst: scalar_lane_q[9]→write_vector_q[657]10.517ns/fanout32; host output clear/load and DDIO clock/pad setup fail. Group2 output LAB FF→instr_debug[10]pad5.631ns is now worst; scalar_group_q[6][10]→write_vector_q[586]still10.605ns/fanout4/X91→X21. op17→probability_sum_q−0.441ns remains broad control. Worst hold host_addr24→host_address24 clockskew4.572/data4.000ns. Group2 is a timing regression, not accepted closure.

## Prior architecture / warnings retained for provenance
- NanoFable4layers,128width,4heads×32,384MLP,4096vocab,context128. Full embedding, affine RMSNorm(gain),QKV/O,RoPE,KV,causalsoftmax,SwiGLU,residual,finalnorm,tiedS8head,greedy/Gumbel selection. No synthesis computeifdef.
- SRAM768KiBparameters/384KiBKV/9KiBvectors. Replaceable pipelined_word_ram: read3edges≤4tiles/4otherwise,writecommit2; llm_bank group/lane adapter read5,currentwritecommit4,wr_busy drain. Parameterread5at24576rows/4≤4096;hostselection+1;ACKafterwritecommit. Old-data collision; payload/storage unreset, reset cancels queued enables/valid.
- Fixed signed A_SCALE, all-S32_MIN eligible-token fallback, ternary10 fault, final-KV write drain; original failures retained. Do not weaken expected values.
- Map276020 score/output pass-through preserves read-during-write;constantdebug13024/13410. Group2 warning10027 is sigmoid_inputs[group_id*8+lane_q[2:0]]: group_id0..3, index0..31; Quartus narrows first constant group to3bits, valid subgroup access. Tests cover all32lanes. Group2 fit only292013optionallicense,15714/169085autopins. Earlier MLAB/pack warnings no longer occur; AUTO_SHIFT_OFF removes252MLAB/33M10K. STA332148 is actual timing failure.
- Native graph warnings TIMESCALEMOD14,WIDTHTRUNC2(10-bit leaf port with96row vector memory; client0..95),WIDTHEXPAND14(context-sized nonnegative address/counter and exp arithmetic). Correctness units/graph pass; no hidden defines. Windows Application Control blocks native math exe4551; ModelSim math used. Native graph was previously allowed for an older revision, later blocked; current actual-IP graph uses ModelSim. No policy bypass.
- Legacy All10 PASS tree2 UTC18:14:12; shared legacy arithmetic unchanged by select edits. Global legacy hash snapshot predates select.
- Pre-IP docs validation:40assets/57diagrams; current41assets/58diagrams verified above. Legacy ISA remains explicitly linked.

## Reproduce / priorities
```powershell
Get-Process -Name quartus_map,quartus_fit,quartus_sta,vsimk -ErrorAction SilentlyContinue
Get-Content docs/verification/timing/fullrtl100_memoryip2/fit.log -Tail 12
Get-Content tests/full_rtl/build/tb_llm_graph.log -Tail 10
# Inspect running jobs first; do not duplicate these commands while they run:
./tests/full_rtl/run_units.ps1
./tools/timing/run.ps1 -Project quartus/llm_soc -Tag NEW_UNUSED_TAG -QuartusBin C:/intelFPGA_lite/18.1/quartus/bin64 -Python C:/Users/khanh/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe
# If graph is run independently after same-source compile:
python tools/llm/merge_unit_evidence.py --start tests/full_rtl/build/ip1_modelsim_start.json --modelsim-graph tests/full_rtl/build/tb_llm_graph.log --output tests/full_rtl/evidence/memoryip_units
# Only after all exact-source gates:
./tests/full_rtl/run_application.ps1 -TimingManifest docs/verification/timing/PASS_TAG/manifest.json
```
1. Hardware tag complete/FAIL; finish actual-IP full graph; archive complete seven units/logs/hashes. SynthesisPASS0DSP0PLL is not post-fit timingPASS. Explain map287013 unused IP ports(data_b/rden_a) in write-onlyA/read-onlyB mode;276020 preserves smallRAM RDW;10027 bounded sigmoid subgroup;constantdebug13024/13410. Fit176251wildcards cover constantdebugpins;56nonconstant outputFFs packed. Keep all warnings.
2. Actual memoryip2 paths: parameter lane3.write_data_q7 duplicate→lane6.IP.write_data_q7 11.147ns; scalar_a4→scalar_product62 11.055ns; SIMD b19/31→product48 10.77ns. Candidate fixes (not implemented): preserve per-bank memory write payload copies with boundary-only dont_merge; pipeline wide scalar/SIMD logic-cell multipliers into signed byte products/pair sums; local per-lane intermediate FFs for scalar route; probability_sum decode only actualwriters. No PLL or vendor compute IP. Keep SDC; no false/multicycle paths. Revalidate hardware/units after RTL edits.
3. Commit/push verified memory milestone with truthful pending/failed timing state. Exclude models/runtime/cache. Continue full>=100MHz gate then meaningful trained paragraph; second model only when supported and gatesPASS.
