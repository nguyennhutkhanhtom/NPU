# NPU resume checkpoint

<!-- reading-navigation:start -->
[Documentation](../README.md) → [Archive](../archive/README.md) → This page

| Reading guide | Document |
|---|---|
| Read first | [Historical context](../archive/README.md) |
| Continue / related lookup | [Current evidence](../verification/optimization_status.md) |
<!-- reading-navigation:end -->

> **Category: HISTORICAL SNAPSHOT — see dated checkpoints below.** This snapshot must not determine current architecture, live status or active tasks.

Updated 2026-10-04 22:25 Asia/Saigon. Repo/reports/hashes are authoritative. Preserve valid changes and immutable evidence; no reset/revert.

## Goal and rules

Full autoregressive graph on RTL; CPU loads weights/config/prompt and tokenizer/decode only. Quartus is the EDA synthesis/timing demo backend, not FPGA board bring-up or ASIC signoff. ASIC-portable compute/control and replaceable SRAM leaf are the priority.

[AGENTS.md](<../../AGENTS.md>): explicit RTL/generate/obvious ownership; no synthesizable task, variable loops, hidden sequential/memory/pipeline datapaths, runtime multiplication/division or vendor compute/control IP. Only SRAM leaf altsyncram. Keep original SDC/test expectations and correct changes.

Pretrained export/application/CPU checkpoint inference requires exact-current all-seven unit/graph PASS AND full-top post-fit>=100MHz, every corner setup/hold/recovery/removal/pulse slack>=0,TNS0,UCP0. No trained application has run under this gate.

## Current cache1: all seven units, portable elaboration and synthesis PASS; timing FAIL73.97MHz

LLM source SHA5abac9ed9dde98138c4e5928fe7638e302ca4bf9a49b38eeafd373826a10fb9e,1036lines. Separate cache_operand_q from second_q:32generated plain FF slices sample k_data continuously; A_KEY/A_WEIGHT consume after O_K_WAIT/k_valid, same accepted response edge as before. second_q only captures binary vector input at B_INPUT0. Removes wide shared cache-enable/mux; adds768payload FF bits, no reset/enable on them. No FSM state, clock, latency, arithmetic or expected-value change. Early attention accumulator clear at A_QUERY remains.

Completed cache1 QSF had GLOBAL_SIGNAL "GLOBAL CLOCK" at u_reset|core_rst_n, a backend reset-routing request only. Keep two standard reset FFs, two-edge release and immediate host_rdata zero/cancellation contract; protocol explicitly checks zero1ns after reset assertion. No IP instantiation/generated clock/SDC exception. Actual broad global routing applied but failed; current cache2 QSF removes that request per measured recommendations.

Timing exec19892 completed22:14:10, all Quartus processes closed. [Manifest](<../verification/timing/fullrtl100_cache1/manifest.json>) current34RTL/3config/all reports/commands/37ZIP and all-seven source/test/log hashes verified before next change. ZIP SHA9924684480f285ec0c9ae4de3865d05994fb7907db724305cac5f90b3b0e8bef. Device5CGXFC9E6F35C7/Quartus25.1std Build1129/seed1/SPEED/STANDARD; SDC10ns/IObudgets unchanged. Map0/12,fit0/4,STA0/2timingwarnings332148,extract0. Fitelapsed55m33/resources52417ALM/49186FF/1186RAMblocks/9515648bits/186pins/DSP-PLL-DLL-HSSI0; UCP0/16of20PASS. Strict gate rejects73.97MHz.

Slow85setup-3.519/TNS-41006.030,hold.252/0,recovery-.938/-7.276,removal1.267/0,pulse3.600/0; slow0setup-2.753/-22915.773,hold.241/0,recovery-.413/-3.066,removal1.718/0,pulse3.548/0. Fast85/0allPASS/TNS0. Fulltable/reports/recommendations in timing hub.

Measured critical setup core_rst_n -> SIMD a_q13bit2,data10.124/routing8.995/twolevels/skew-3.115; recommendations explicitly Remove global routing resources at core_rst_n~CLKENA0. ForcedGLOBALrequest actually mapped6106allloadsGCLK1, broadening previousautomatic async-onlyglob1290/nonglob4502enable. This backend candidate failed; next remove forced request only, retain exact all-seven-PASS cache1 RTL/2FFreset/hostimmediatezero/SDC. Recovery stillfails core_rst_n->host_rdata10/2/12/4/8/5/7/1,worst-.938/data8.341/skew-2.317. No timing benefit claimed for cache split while forced-global path dominates. No trained application.

All-seven exec28687 completed PASS22:02:59, graph vsim40304 closed. Current all-seven archive (`tests/full_rtl/evidence/cache1_all_units/results.json`; historical target unavailable in this checkout): exact34RTL/eighttestinputs/helper/model/log/binding hashes verified, compile/runtime0warnings. Graph4229462compute clocks/prompt2/selected3/layerexec16/hostcommands196619/causal checked, elapsed51m14. No expected/test changes. Earlier six archive (`tests/full_rtl/evidence/cache1_six_units/results.json`; historical target unavailable in this checkout) retains its capture-time RUNNING graph status; immutable. Rootunit_results nowPASS.

[Current vendor-free elaboration](<../verification/portable_elaboration_cache1/results.json>) PASS22:04:25, exec12311 closed; USE_QUARTUS_MEMORY=0/run0/no weights/inference, reuses verified cache1_questa_work. No vendor library binding;24module units/14names/0errors0warnings. Behavioral SRAM, not foundry macro/ASIC synthesis/signoff. Single Questa license is free.

Docs/source guide current hashes/excerpts PASS34assets/150groups/4528RTLlines/1059LUTentries/51rendered/1919links. Updated LLMSoc diagram shows direct vector/math, held binary operand and independent KV payload FFs; visually checked. Old changed PNG/SVG and diagram metadata saved under ignored tools/docs/output/attention1_saved. [Current policy review](<../verification/rtl_policy_cache1/results.json>):56loops=41generate/13small static/2elaboration,15functions=13pure runtime/2geometry,62arithmetic-symbol statements are geometry/index factors. Manual/lexical source review, not functional/timing proof. No source/test changes are planned for next backend routing comparison; preserve exact-current all-seven evidence.

## Latest completed full-top timing: attention1 FAIL92.19MHz

[Manifest](<../verification/timing/fullrtl100_attention1/manifest.json>), [ZIP](<../verification/timing/fullrtl100_attention1/source_archive.json>), [timing hub](<../verification/timing/README.md>). Completed20:52:43; all old jobs closed. Source/config/37ZIP/report/command/current-at-that-time seven-unit hashes verified before cache1 edit. Map0errors12warnings/fit0errors4warnings/STA0errors2warnings332148. Fitted52799ALM/48311FF/1186of1220RAMblocks(97%)/9515648bits(76%)/186pins; DSP/PLL/DLL/HSSI0. UCP0;17/20checks PASS, strict gate rejects92.19MHz.

Slow85 setup-.847/TNS-43.132,recovery-.122/-.739,hold.090/0,removal.910/0,pulse3.600/0. Slow0setup-.369/-6.553; hold.241/0,recovery.124/0,removal3.532/0,pulse3.548/0. Fast85/0 all fivechecks PASS/TNS0. SourceZIP SHA0f9badde7a854d76f1edb6541af9f1547d132579c39342d94a14968dd43c059e.

Measured setup op6/O_K_WAIT -> second_q341,data10.568/routing9.314/onelevel/skew-.179; recommendations duplication/inter-path competition. Parameter lane3write_data6 stage also-.579. Recovery core_rst_n -> host_rdata11/12/6/9/13/3/7/2,data10.614/routing9.504. Cache1 targets first/reset paths; no timing improvement claimed yet. Hold fix host_addr/host_wdata D3setting7 achieved every corner; preserve backend settings.

## Verified preceding source and retained evidence

- Attention1 all-seven (`tests/full_rtl/evidence/attention1_all_units/results.json`; historical target unavailable in this checkout) PASS20:35:33 for source51ef7ae59847a9b082916872fc3512dbc0d890011d5b8134c8dfccb0f8985811. Compile/runtime0warnings; graph4229462compute clocks/prompt2/selectedtokens3/layerexec16/hostcommands196619/causal checked. Math503/reset9/LUT513/bit1536; operators17/checks3460/scalar128/clamp128/fullcontext128attention. Current cache1 source differs.
- [Attention1 vendor-free elaboration](<../verification/portable_elaboration_attention1/results.json>) PASS24module units/14names/0errors0warnings, USE_QUARTUS_MEMORY=0/run0/no weights or inference. Behavioral SRAM, not foundry macro/ASIC synthesis/signoff. Current cache1 elaboration also PASS as linked above; old attention1 evidence remains immutable.
- [SRAM ASIC guide](<../design/asic_memory_binding.md>):72explicit leaves, common-clock1R1W/rawread1edge/OLD_DATA/no storage reset. Wordread3/4/write2; bankread5/write4/drain; parameterread4/5+hostlaneedge/writeackaftercommit. Four small inferred controller arrays with visible ownership. Replace technology leaf/views, preserve latency/collision/reset; compute interfaces unchanged.
- Reset2FF release and continuous SIMD captured-operand/nine-clock response remain verified. Prior fanout2 FAIL96.67MHz/setup+hold, fanout1 FAIL98.63MHz/setup+hold, release1 FAIL91.61MHz; all immutable. Legacy49.49MHz is not full llm_soc. Legacy10regressions unaffected; do not rerun needlessly.
- Optional cancel probe (`tests/full_rtl/evidence/host_cancel_gap1/results.json`; historical target unavailable in this checkout) PASS7phases/14storagechecks/oneidleedge. Accepted writes may commit after response cancellation; no rollback promise. No testcase/expected-value relaxation.
- [Policy Git transfer check](<../verification/rtl_policy_attention1_git/results.json>) retains initial metadata-byte failure from CRLF/LF staging; payload/helper/rules/source hashes identical. Cache1 evidence attribute added before staging. [Docs refresh check](<../verification/doc_refresh1/results.json>)36pages/manifest byte-idempotence PASS after preserving trailing blank line/group ownership.

## Commits, cleanup and application

Latest pushed70c794d full cache1 timingFAIL73.97/recommendations/docs;35704b0 cache1 all-seven/vendor-free/docs;41eea1a cache1 AS/six-unit/structure/docs; preceding b9699a7 full attention1 timingFAIL; b3d3033 all-seven/portable/docs,9a512d8 policy/docs,a2fa161 early-clear/A&S/six units. Cache1 timing source/config/report/ZIP hashes passed both workspace and index checks before commit and QSF edit. Current cache2 routing-only backend comparison is uncommitted/running. No weights/vendor libraries/large build DB/secrets in repo. Isolated quartus_cache*/ projects ignored; active DB retained.

Unused helpers archived/removed with SHA ZIP; reachable legacy/test sources retained. Inactive12Quartus DB directories/1864217551bytes removed only after six historical ZIP/report hash checks; all reports/active DB/model cache retained. [Cleanup record](<quartus_database_cleanup_20261004.json>).

Pinned NanoFable seed1 model/assets remain ignored; application default96newtokens/temp166/seed7/min64/context128. Application monitor compile-only PASS, not trained inference. O5 profiling gave no speed benefit; defaultO4 retained. Numeric/token matching differs from decoded quality; run actual RTL paragraph then additional compatible model only once gates pass. No fake continuation or CPU replacement.

## Reproduction and priority

```powershell
Get-CimInstance Win32_Process | Where-Object { $_.Name -match 'quartus|vsimk' } | Select ProcessId,ParentProcessId,Name,CommandLine
python docs/source_guide/validate.py
./tools/timing/run.ps1 -Project quartus_cache1/llm_soc -Tag FRESH_TAG -QuartusBin C:/altera_lite/25.1std/quartus/bin64
./tests/full_rtl/run_units.ps1 -SimBin C:/altera_lite/25.1std/questa_fse/win64 -Questa -MemoryModelManifest tests/full_rtl/build/questa25_model/manifest.json -TimingManifest docs/verification/timing/fullrtl100_attention1/manifest.json -WorkLibraryName FRESH_WORK -EvidenceTag FRESH_TAG
# ONLY after exact-current unit/full timing gates PASS:
./tests/full_rtl/run_application.ps1 -TimingManifest docs/verification/timing/PASS_TAG/manifest.json
```

Python C:/Users/khanh/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe; Questa/Quartus bins C:/altera_lite/25.1std/questa_fse/win64 and quartus/bin64. Unsigned helpers blocked by Windows Application Control; no bypass. Single active Questa simulation license.

1. Current timing exec11326 RUNNING, quartus_cache2/llm_soc/tag fullrtl100_cache2; map10812 closed PASS0errors12warnings22:23:58/elapsed5m41, Fitter22564 active22:24. [A&S archive](<../verification/synthesis/cache2/manifest.json>)34RTL/3configuration/37ZIP hashes verified. No Questa process. CanonicalQSF removes only forcedGLOBALrequest plus explanatory comments;34RTL/eighttestinputs/10nsSDC unchanged and verified against cache1 all-seven snapshot. Do not launch another build or edit frozen inputs.
2. [Cache2 source/config ZIP](<../verification/timing/fullrtl100_cache2/source_archive.json>)37members SHA8ff7093e55604550dae31f3f12b4718fa45f6eb6a0ba4a87d1b5bb380c9cf7cf. Initial raw-byte SDC precheck failed CRLF-vs-LF only; corrected canonical-LF comparison PASS/currentcanonical3cfg match initialsnapshot. Quartus recorder also uses canonicalLF; constraints unchanged. A&S archived; archive fresh fullreports when complete; check actual routing/corners/UCP/resources/warnings. Tests unchanged, no rerun needed absent RTL/test edits.
3. Only exact-current all-seven+full100MHz gates permit pinned NanoFable actual RTL paragraph/reference; assess matching separately from coherence, then second compatible language model when supported.
