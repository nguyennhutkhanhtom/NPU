# Exact arithmetic throughput optimization, version 3

> **Category: REVIEW — 2026-10-06.** This snapshot must not determine current architecture, live status or active tasks.

Approval: the user approved the supplied phased optimization ideas and the seven corrections presented in the preceding review by requesting implementation. This document records that approved scope; no additional approval is required for those changes.

## Inputs and baseline

RTL root: `D:/2151097_Nguyen Nhut Khanh/Verilog Source code`, explicitly identified in the preceding source-based review. Top: `llm_soc`. No separate old specification was supplied. Existing arithmetic, host, reset, error, overflow, causal ordering and token selection behavior are derived from the current RTL and independent synthetic reference tests. The new requirements are the attached phased optimization plan and the preceding review corrections. Existing dirty workspace changes are part of the task-start baseline and must be preserved.

The task-start snapshot is retained in `docs/verification/optimization_baseline`. Its recorded unit/graph evidence is PASS and matches the task-start RTL/test hashes. The historical `npu100_b2` full-top timing manifest matches that baseline RTL and backend configuration but reports FAIL, 98.39 MHz and -0.164 ns worst setup slack. Synthetic verification is permitted; pretrained execution requires exact-current all-seven PASS and full-top >=100 MHz at all corners, nonnegative setup/hold/recovery/removal/pulse slack, TNS=0 and no unconstrained paths. The final candidate satisfies these hardware verification conditions; no pretrained application was requested or executed.

## Requirement comparison and affected files

| Requirement | Current source evidence | Intended behavior and affected files |
|---|---|---|
| Record performance | Graph executes serially; no transaction profile | Optional counters in `llm_soc.sv`; testbench profiles cycles and accepted transactions, without production counter cost |
| Single host parameter read | `llm_soc.sv` host read enable includes H_WAIT | Request only in H_READ; preserve cancellation and own-commit-before-ACK contracts |
| Reuse RoPE coefficients | G_RQ/G_RK each load two words | G_RK retains table but reads K vector before rotation; only sequential Q/K reuse |
| Compact return and optional debug | Six OP_COUNT-wide held continuations and encoder | Explicit compact destination enums with constant state mapping; parameter controls debug encoder |
| Cache immutable operands | L_INPUT/H_INPUT repeatedly access vector SRAM | Portable 12-row operand cache, exact source/shape ownership and explicit invalidation; head reloads final norm input per entry |
| Cache head scales | H_SELECT reloads each vocabulary row | Keep one packed word for eight rows, select 24-bit coefficients in 32-bit slots |
| Pack linear stores | L_STORE issues one masked transaction per scalar | Use existing write_vector_q, flush at lane 31, preserve final-lane capture and memory drain |
| Dedicated ternary dot | Linear uses general 24x32 arithmetic | `ternary_dot32.sv`: explicit sign/zero terms, widened balanced pipelined tree, synchronized reserved-weight fault |
| Fuse attention probability/value passes | Separate probability array and V traversal | Same probability and ascending-time products/sum; clear accumulators per head, normalize only after final accumulation |
| Exact divider and sigmoid throughput | Serialized divider and sigmoid lanes | Profile first; implement a bounded number of replicated structural units if beneficial; preserve RNE, sign and saturation |
| SIMD streaming | Operand capture and valid gated by busy; product/sum have different stage positions | `llm_math.sv` keeps legacy default mode and adds a streaming mode with aligned product/sum response; sustained and sparse inputs verified independently |
| Streaming head and attention | One outstanding request and arithmetic operation | Local request/response tags and counters, pipeline drain, immutable operand cache; preserve PRNG order, ties and selected tokens |
| Linear prefetch | Packed word supplies four chunks | Bounded local lookahead; preserve four-chunk word geometry and invalid-weight handling |
| Structural organization | Operator control embedded in top | Extract engines/helpers only after exact behavior and performance changes pass; update file lists and preserve public interface |

Supporting scope: `tests/full_rtl/tb_math.sv`, `tb_operators.sv`, `tb_graph.sv`, `tb_protocol.sv`, `host_cancel_contract.sv`, runners as necessary to compile and verify the added modules, `quartus/llm_soc.qsf` file list and backend-only physical settings, and documentation/evidence tools. Arithmetic references must not be weakened. Existing fixture state injections may be adapted to compact enums and additional latency, retaining independent expected values.

## Strategy and minimal-change rationale

Use sequential checkpoints: baseline; control/cache/store traffic; ternary datapath; attention fusion and measured replication; SIMD protocol/streaming; structural cleanup. This is the single recommended strategy because each checkpoint isolates an exact semantic transformation. Reuse existing register owners and write payloads, share operand storage where operator lifetimes do not overlap, and keep the graph phase IDs and host interface stable. Logical arrays must not instantiate vendor memory; arithmetic must use structural mux/add/subtract/shift logic. Runtime multiply/divide operators and synthesis tasks are prohibited. Approximate reciprocal normalization is excluded from the exact path; no numerical tolerance is introduced.

Storage cache reuse is confined to proven consecutive immutable-source operations. Reset, new launch, producer writes and faults cancel validity. SIMD streaming must align both product and reduction results; removing busy gating alone is insufficient. Outstanding memory/arithmetic responses must retire before resource ownership changes. Output grouping does not imply fewer lane data writes, and traffic reduction does not imply equal cycle or PPA improvement. All benefits are reported as observed measurements.

## Approved validation

1. Existing synthetic runner, with fresh tags/libraries: `tests/full_rtl/run_units.ps1 -SimBin C:/altera_lite/25.1std/questa_fse/win64 -Questa -MemoryModelManifest tests/full_rtl/build/questa25_model/manifest.json -TimingManifest docs/verification/timing/fullrtl100_cache2/manifest.json -WorkLibraryName <fresh> -EvidenceTag <fresh>`. Run the six groups at intermediate checkpoints and all seven including graph for final RTL. Archive logs and source/test hashes before later runs.
2. Existing host cancellation contract: `tests/full_rtl/run_host_cancel_100mhz.ps1 -WorkLibraryName <fresh> -EvidenceTag <fresh>`.
3. Existing portable elaboration: `tests/full_rtl/run_portable_100mhz.ps1 -WorkLibraryName <all-seven library> -EvidenceTag <fresh>`.
4. Full-top post-fit timing: `tools/timing/run.ps1 -Project quartus/llm_soc -Tag <fresh> -QuartusBin C:/altera_lite/25.1std/quartus/bin64 -Python C:/Users/khanh/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe`. Preserve unchanged SDC and all failing reports. Re-run only after a relevant RTL/backend correction.
5. Extend existing fixtures with meaningful directed checks: exact cache traffic and invalidation, Q/K table reuse, packed final-lane payload, S24_MIN and reserved ternary weights, streaming throughput/bubbles/reset and product/sum alignment, attention context boundaries and exact normalization, PRNG/tie order. New standalone arithmetic tests may be compiled and executed with the same Questa tools and source hash recording.

Pretrained execution is not an optimization test and remains prohibited until the existing application gate passes. Quartus results are an FPGA EDA demonstration, not ASIC signoff.

## Reporting

Final evidence must map implemented requirements to source and actual checks. RTL change percentage uses nonblank, non-comment task-specific added+deleted code lines divided by the task-start count across the entire supplied RTL tree. Tests, reports, blank/comment-only edits and pre-existing changes are excluded. No result is claimed before inspection. Implementation status: complete; all-seven functional, host cancellation, portable elaboration and full-top all-corner post-fit timing checks PASS.

## Implemented scope and traceability

| Requirement | Final implementation | Verification evidence |
|---|---|---|
| Control, traffic and caches | `llm_soc.sv`: compact explicit continuation enums, optional debug/performance logic, H_READ-only host request, tagged Q/K RoPE reuse, shared 12-row operand cache, eight-row head scale cache and full-row linear writes | Protocol and independent operator references; final graph checks exact transaction geometry |
| Exact ternary arithmetic and prefetch | `ternary_dot32.sv`, `llm_linear_engine.sv`: widened balanced reduction, aligned reserved-code fault, two-word FIFO credits, local row accumulation and response drain | S24_MIN/reserved tests, FIFO bound and ownership assertions, nonuniform independent S128 outputs, four reset probes |
| Streaming SIMD and row engines | `llm_math.sv`, `llm_head_engine.sv`, `llm_attention_engine.sv`: independent product/sum validity, four ordered head requests, causal QK streaming and pipelined exact score scaling | Sustained/sparse/reset scoreboards; exact head score, selected token and PRNG state; causal address checks |
| Attention and sigmoid throughput | `llm_soc.sv`, `llm_attention_normalize.sv`: ascending-time probability/value fusion, four exact divider lanes with lane zero shared by RMSNorm, four ordinary sigmoid lanes | Exact context-4/context-128 outputs, signed normalization boundary/tie checks, cancellation/reset tests and original sigmoid references |
| Structural separation | `isqrt_u64.sv`, `sram_word_tile.sv`, legacy `norm.sv`/`banked_word_ram.sv`, full-top and legacy Quartus file lists | Helper bodies extracted without arithmetic changes; full-top file list excludes legacy wrappers; legacy paths retained and `quartus/matmul_free.qsf` includes the extracted dependencies for compatibility |

The detailed resource/latency/traffic contracts are in `docs/design/exact_throughput_optimization.md`. Approximate reciprocal arithmetic is excluded, as approved. The full graph, host interface, scaling, output buffer and sampler remain parent-owned. Physical settings and unchanged timing constraints remain in the backend project.

## Observed intermediate measurements

These are measured compute clocks from the same synthetic operator geometry; they are not wall-clock or ASIC performance estimates.

| Operator | First ternary checkpoint | Final datapath checkpoint | Ratio |
|---|---:|---:|---:|
| Q linear | 5,677 | 3,373 | 1.68x |
| Down linear | 14,693 | 4,709 | 3.12x |
| Gate linear | 16,949 | 10,037 | 1.69x |
| Head | 367,646 | 121,886 | 3.02x |
| Attention, context 4 | 9,926 | 2,762 | 3.59x |
| Attention, context 128 | 34,726 | 15,162 | 2.29x |
| SiLU | 4,134 | 1,254 | 3.30x |

Evidence: `tests/full_rtl/evidence/opt_dot1_selected`, `opt_prefetch1_selected` and `opt_cancel1_selected`. The last selected operator run passes 21 operator cases and 5,456 independent checks, including all four newly added reset probes. The independent extended math checkpoint passes legacy arithmetic, streaming, ternary and normalization scoreboards.

`tests/full_rtl/evidence/opt_host1/results.json` records current-source host cancellation PASS: seven phases, fourteen checks, accepted-write commitment and own-commit-before-ACK. No application was executed.

Compilation failures and interrupted attempts are retained rather than overwritten: `opt_final1_compile_failed` (cleanup anchor repaired from verified task checkpoint), `opt_final2_failed` (testbench observation delta repaired), `opt_final3_cancelled`, timing `opt_fulltop1` (inline generate index parser compatibility) and `opt_fulltop2` (parenthesized sized-cast negation parser compatibility). These directories are not PASS evidence. Final all-seven and full-top results are recorded below.

Timing attempts `opt_fulltop3` and `opt_fulltop5` stop with QSYN internal worker-pipe errors and zero RTL errors. The latter reproduces the error with one worker. `opt_fulltop4` was interrupted after identifying an overridden worker setting. The fresh `opt_fulltop6` attempt uses one worker outside the process sandbox. These failures do not establish any timing or utilization result. The clock constraints and physical delay assignments have not been relaxed.

`opt_fulltop6` passes synthesis outside the sandbox. Its map reports and configuration
are retained; fitting was interrupted to restore the original ALL worker concurrency
for the remaining expensive check. `opt_fulltop7` is the new full-top attempt outside
the sandbox, with baseline tool concurrency and unchanged portable RTL/SDC/physical
delay settings. The temporary one-worker setting is absent from the final project.

## Synthesis and code-change measurements

The final `opt_fulltop7` Analysis & Synthesis stage passes with zero errors and 22 warnings.
Pre-fit registers are 63,782 versus 53,486 in the matching task-start baseline;
memory bits are 9,516,544 versus 9,515,648, and DSP blocks remain zero. Post-fit
utilization and all-corner timing PASS are recorded below. The warnings comprise
an unused retained chunk register, narrow array-index diagnostics, unused
vendor memory ports, inferred-memory read-during-write pass-through logic, and
constant debug/output bits. No warnings have been suppressed.

The `opt_final4` suite has passed all seven groups with zero compile
and runtime warnings. Extended
math results include 503 legacy transactions, 1,635 streaming scoreboard checks,
814 ternary transactions and 672 exact normalization lane comparisons. The final
source hashes align across the live 41 RTL/LUT assets, regression start snapshot,
timing start snapshot and passing host cancellation manifest.

Task-specific code counts for this verified candidate are **5,165 baseline RTL
code lines, 828 added lines and 265 deleted lines**. The change percentage is
`(828 + 265) / 5165 * 100 = 21.161665%`. This comparison uses the task-start
content snapshot, includes moved helper code as additions/deletions, and excludes
comments, blank lines, tests, reports and pre-existing workspace changes.
Changed RTL files are `llm_soc.sv`, `llm_math.sv`, `ternary_dot32.sv`,
`llm_linear_engine.sv`, `llm_head_engine.sv`, `llm_attention_engine.sv`,
`llm_attention_normalize.sv`, `isqrt_u64.sv`, `sram_word_tile.sv`, `norm.sv`
and `banked_word_ram.sv`. The final archive retains per-file raw counts.

## Final functional verification

`tests/full_rtl/evidence/opt_final4_all/results.json` records **all seven groups
PASS**, with zero compile/runtime errors or warnings and actual vendor RAM
bindings verified. The immutable archive retains all logs, compiler diagnostics,
source file list, current RTL/tests, hashes and per-file RTL change counts.

The same synthetic graph now requires **1,066,965 compute clocks**, versus the
preserved **4,254,046-clock** baseline: **3.987053x speedup** and **74.918818%
fewer compute clocks**. It retains two prompt tokens, three selected token IDs
(all 3), sixteen transformer layer executions, original status/overflow/error
checks, causal addresses and graph phase visits. All exact traffic assertions
pass: 77,756 parameter reads, 1,828 vector reads, 1,564 vector writes, 320 KV reads
and 128 KV writes. Profiling records 50,548 shared SIMD starts, 2,083 divider
starts and 6,144 sigmoid starts. The internal performance interval is 1,066,966
clocks, including one graph entry clock excluded by the preserved benchmark's
external running interval. These compute counts do not estimate host loading,
simulation wall time, pretrained model quality or ASIC performance.

`docs/verification/portable_elaboration_opt_final4/results.json` records
vendor-free full-top **ELABORATION_PASS**, zero errors/warnings, with
`USE_QUARTUS_MEMORY=0` and no vendor memory/control/arithmetic modules loaded.
This is elaboration, not ASIC implementation or timing signoff. The independently
recorded host cancellation PASS remains source-current. No pretrained application
or pretrained reference inference has been executed in this task.

The frozen functional candidate has 5,165 task-start code lines, 828 additions,
265 deletions and **21.161665%** task-specific RTL code change. The archived
`rtl_changes.json` retains all eleven changed-file counts. The final `opt_fulltop7`
post-fit result also passes with matching source/configuration hashes. The hardware
verification prerequisites for pretrained execution are satisfied for this candidate;
no pretrained application was executed.

The observed entry-inclusive phase profile is:

| Phase group | Profile clocks |
|---|---:|
| Seven linear matrices | 611,168 |
| Language head | 365,661 |
| Attention | 41,808 |
| SiLU | 20,080 |
| RMSNorm, including final norm | 13,545 |
| Embedding, RoPE, KV stores, residual/Gate-Up operations and graph transitions | 14,704 |
| Total | 1,066,966 |

## Final physical verification and resource tradeoff

`docs/verification/timing/opt_fulltop7/manifest.json` records **TIMING_100MHZ_PASS**
with verified current source and configuration hashes. Device `5CGXFC9E6F35C7`,
seed 1, ALL worker concurrency, the 10 ns clock and physical delay assignments
match the task-start backend settings. No timing exceptions or test tolerances
were added to obtain closure. The full-top file list includes the extracted
engines/helpers; the legacy project also receives the two extracted helper
dependencies so its existing module references remain compilable.

| Corner | Fmax (MHz) | Setup (ns) | Hold (ns) | Recovery (ns) | Removal (ns) | Pulse (ns) |
|---|---:|---:|---:|---:|---:|---:|
| Slow 1100 mV, 85 C | 100.78 | 0.077 | 0.245 | 0.123 | 1.599 | 3.600 |
| Slow 1100 mV, 0 C | 101.50 | 0.148 | 0.232 | 0.332 | 3.666 | 3.548 |
| Fast 1100 mV, 85 C | 148.41 | 3.262 | 0.131 | 4.535 | 2.330 | 3.801 |
| Fast 1100 mV, 0 C | 161.60 | 3.812 | 0.115 | 5.473 | 0.976 | 3.790 |

Every reported timing check has TNS zero. All unconstrained setup/hold path,
clock and input/output port counts are zero. The worst setup path is
`vector_q[383] -> input_cache_q[6][383]`, with 9.627 ns data delay and -0.196 ns
clock skew. The 0.077 ns setup margin is positive but small; later RTL or backend
changes require fresh timing evidence.

| Fitted resource | Matching task-start baseline | Final candidate | Change |
|---|---:|---:|---:|
| ALMs | 53,974 | 59,605 | +5,631 (+10.43%) |
| Registers | 55,466 | 66,924 | +11,458 (+20.66%) |
| Memory bits | 9,515,648 | 9,516,544 | +896 |
| RAM blocks | 1,186 | 1,186 | 0 |
| DSP blocks | 0 | 0 | 0 |

The measured graph speedup therefore costs additional portable register/logic
resources. Quartus fitting passes with zero errors and four warnings: unavailable
LogicLock licensing, incomplete I/O assignments, missing exact pin locations
(the accompanying critical warning), and ignored fast-output assignments for
constant destinations. STA and report extraction have zero errors/warnings.
The physical warnings are retained and have not been suppressed. These results
cover the default four divider/four sigmoid lanes and the configured EDA backend;
other replication geometries, board deployment and ASIC PPA/signoff are not
established by this task. All task-start changes and immutable evidence are preserved.
