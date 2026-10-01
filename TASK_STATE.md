# NPU resume checkpoint

Updated 2026-10-02 (Asia/Saigon). Repo, hashes and actual reports override chat history.

## Objective / gates

Full autoregressive graph on RTL; CPU loads parameters/config/prompt and tokenizes/decodes only. Exact-current-source post-fit >=100 MHz at every corner; setup/hold/recovery/removal/pulse clean, TNS=0, unconstrained=0. No false/multicycle exceptions to hide failures. Pretrained application only after hardware and six-group current unit gates. Numeric matching and paragraph quality are separate. Quartus is FPGA evidence, not ASIC signoff.

## Preservation / active work

- Workspace `D:\2151097_Nguyen Nhut Khanh`, main, HEAD `26ba5dbcc1e62b64236f036c7f244da145ec5cd2`, remote https://github.com/nguyennhutkhanhtom/NPU.git. Valid uncommitted changes remain; no reset/revert. No new commit/push yet.
- **`fullrtl100_local1` completed/archive**, exact source/config hashes and 41-asset source zip. No Quartus build running; no tags overwritten. Timing FAIL84.49MHz.
- **Six-group units PASS** UTC17:40:58 Oct1 (00:40:58 Oct2 local): math503/reset7/LUT513,RAM17,protocol23/cancel6,selection14,operators17/2820,graph2944461clocks/16layer executions/3RTLtokens/196619hostcommands. Hashes match current source/tests; archived `evidence/local1_units/`.

## Full-top timing facts

Device `5CGXFC9E6F35C7`; `quartus/llm_soc.qsf`, speed/standard/seed1; `llm_soc.sdc` clock10ns,input0.5..2ns,outputsetup2/hold0.5ns,derived uncertainty,no exceptions. Real127I/O; board pinout unspecified.

| Immutable tag | Result / evidence |
|---|---|
| `fullrtl100_tiled` | A&S PASS0/6,fit PASS0/4; **timing FAIL70.41MHz**. 24125ALM,16132reg,1111/1220RAM,9519744bits,104DSP. Slow0 setup−4.202/TNS−4791.870; Slow85−3.781/−5323.438. SIMD/scalar→vector write13.531/13.480ns. |
| `fullrtl100_pipeline1` | Map failed QSYN named-pipe sandbox error. Log/snapshot preserved; new-tag outside-sandbox retry approved automatically. No auto-review rejection. |
| `fullrtl100_pipeline2` | A&S PASS0/6,fit PASS0/4; **timing FAIL83.58MHz**. 23060ALM,19958reg,1111RAM,104DSP. Slow85−1.965/TNS−669.972; Slow0−1.518/−258.929. Shared KV write address→M10K11.698ns; read-tile fanout and op decode→SIMD also critical. |
| `fullrtl100_local1` | A&S PASS0/6,fit PASS0/4; **timing FAIL84.49MHz**. 22873ALM,23168reg,1187/1220RAM,102DSP. Slow85−1.836/TNS−952.596; Slow0−1.687/−260.523. Parameter SRAM→host_rdata11.426ns, sigmoid y0→y_raw11.472ns; KV shared→local addresses also fail. |

Completed manifests have exact source/config hashes and all four corners. Fast setup and all hold/recovery/removal/pulse pass; other TNS0, unconstrained0. STA tool success is not timing PASS. Byte-exact source zips reconstruct uncommitted revisions; extract separately and rename `rtl` to `Verilog Source code` for QSF relative paths. Legacy49.49MHz is matmulfree, not llm_soc.

## Correctness fixes / tests

- Nonuniform128-position attention found unsigned A_SCALE part-select: negative scores saturated positive; expected−38/actual217. Fixed signed operand. Original FAIL/diagnostics in `tests/full_rtl/evidence/nonuniform_first/`; signed candidate five groups PASS in `evidence/signed_candidate/`.
- Pipeline2 adds per-lane S64capture/RNE/S24clamp, scalar saturation→selected lane, residualadd→clamp. ReciprocalU25 from epsilon42950/root>=207. Pipeline2 five groups PASS; graph2752085clocks/16layer executions/3tokens, archived `evidence/pipeline2_units/`.
- Selection all eligible S32_MIN returned masked0. Original FAIL in `evidence/selection_min_fail/`. Current fallback is lowest eligible ID (1 when EOS allowed,else3); sixth group PASS14checks. CPU independent reference masks with S64_MIN below S32_MIN; exporter validates config widths/final gain range. No pretrained run.
- Reserved ternary code10 previously acted as zero. Current selected-code detection faults; added operator fixture PASS without weakening expected values.
- Legacy `tests/run.ps1 -Block All` PASS10 UTC16:01:51 Oct1 after tiling: host168,sqrt4301/RNE37189/coefs900/maxcompose54,rowwise1800/S128,SRAM47,sigmoid1638400. Functional legacy RTL unchanged since; scale_compose LF only. Global hashes predate full-top changes.

## Current architecture / contracts

- Full llm_soc owns embedding, affine RMSNorm gain,Q/K/V/O,RoPE,KV,causal attention/softmax,SwiGLU,residual,final norm,tied head,greedy/Gumbel selection,prefill/autoregressive loop. No CPU graph/intermediate/logit/token injection or SYNTHESIS/QUARTUS compute branches.
- Fixed NanoFable:4layers,128width,4heads×32,384MLP,4096vocab,context128. SRAM768KiBparams/384KiBKV/9KiBvectors. Ignored checkpoint SHA256 `cfa114a8e411c25e89f8b507cb5886785f89132352743f26cd23a7cbaab863ae`.
- banked_word_ram tiles1024 words; leaf1read+1write,1edge old-data collision; contents/output unreset. Parameter wrapper2edge read.
- **llm_bank_ram2edge read**: local per-lane address/en/data capture, leaf executes nextedge; queued write1edge. Reset cancels enables/valid, keeps storage/payload. dont_merge only at replaceable SRAM boundary retains locality. Adapter17checks PASS (mask/collision/back-to-back/reset).
- Operator FSM93one-hot/reversecase; debug7-bit index. Shared multiplier captures S39/S25 operands. Graph test checks onehot everycycle. Reset must span rising edge for synchronous operator state; graph/host/valid asynchronous.
- Synthetic graph host-loads24576parameter rows,prompt[5,3],deterministictoken3 via tied embeddings/zero projections; checks16layers/causalreads. Verification fixture, not trained quality.

## Warnings / documentation

- Map276020 inferred score/output collision pass-through;13024/13410 constantdebugpins. Fit292013 optionalLogicLock unavailable;15714/169085 boardproperties/autopins unspecified;176251 fast-output wildcard constantpins. Old STA332148 is genuine failure. Review new reports before acceptance.
- Docs hub `docs/README.md`, full design `docs/design/full_rtl_language.md`; validator PASS38assets/34main diagrams/148groups/4296RTLlines/1044LUTlines/1756links,55/55diagrams rendered and changed SRAM diagram visually checked. Review authored explanations after source edits.
- Application gate requires six named groups and exact current full timing evidence. Exporter/reference unexecuted. Numeric matching, meaningful paragraph and supported second model remain pending.

## Commands / priority

```powershell
Get-Process -Name quartus_fit,quartus_sta,vsimk -ErrorAction SilentlyContinue
Get-Content docs/verification/timing/fullrtl100_local1/fit.log -Tail 20
Get-Content tests/full_rtl/build/tb_llm_graph.log -Tail 10
# Do not overlap active units/build; new builds require a NEW unused tag.
./tests/full_rtl/run_units.ps1
./tools/timing/run.ps1 -Project quartus/llm_soc -Tag NEW_UNUSED_TAG -QuartusBin C:/intelFPGA_lite/18.1/quartus/bin64 -Python C:/Users/khanh/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe
$env:DOCS_BROWSER_PATH='C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'
node tools/docs/render.cjs
python docs/source_guide/validate.py
# Only after exact-current gates:
./tests/full_rtl/run_application.ps1 -TimingManifest docs/verification/timing/PASS_TAG/manifest.json
```

1. Commit/push verified six-group functional/full-fit milestone with honest84.49MHz failure; exclude weights/build caches/secrets.
2. Pipeline parameter SRAM response, reduce address fanout/feedback muxes and pipeline sigmoid slope/product/RNE per actual critical paths. Rerun affected legacy tests/six units/new timing tag; no constraint relaxation.
3. Prepare compiled RTL simulator in ignored build cache. MSYS2 GCC12 exists; Verilator5.050 package fetched/hash verified, needs current local winpthread DLL. No system install/pretrained execution.
4. After all gates PASS run trained numeric preview then paragraph on RTL. RTL edits invalidate gates. Assess quality separately; second checkpoint only if supported.
