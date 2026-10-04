# Timing FPGA và tối ưu critical path

[Project](../../../README.md) → [Tài liệu](../../README.md) → [Verification](../README.md) → **Timing**

Trang này ghi cách đọc report post-fit, constraints và thay đổi RTL dựa trên critical path. Phần full graph dùng Cyclone V C9; các snapshot legacy bên dưới dùng thiết bị riêng được ghi trong manifest. Các phép đo là FPGA demo, chưa xác nhận ASIC signoff.

## Fanout2 result: 96.67 MHz, setup/hold FAIL

[Manifest](fullrtl100_fanout2/manifest.json), [source ZIP](fullrtl100_fanout2/source_archive.json) and [unchanged seven-group regression](../../../tests/full_rtl/evidence/pipeline3_all_units/results.json) match34RTL/3configuration hashes. Extraction complete19:29:55 on04Oct2026. Same CycloneV5CGXFC9E6F35C7/QuartusLite25.1std Build1129/seed1/SPEED/STANDARD,10ns SDC and I/O budgets. Map0errors12warnings, fit0errors4warnings, STA0errors2warnings332148. Resources51888ALM/48214FF/1186RAMblocks/9515648bits/186pins; DSP/PLL/DLL/HSSI0. UCP0.17/20checks PASS. Synthesis/fitting PASS, timing FAIL; no pretrained application.

| Corner1.1V | Setup slack/TNS ns | Hold | Recovery | Removal | Pulse |
|---|---:|---:|---:|---:|---:|
| slow_1100mv_85c | -0.345/-62.291 | -0.093/-0.153 | 2.654/0.000 | 1.190/0.000 | 3.600/0.000 |
| slow_1100mv_0c | -0.116/-0.834 | 0.235/0.000 | 2.977/0.000 | 1.118/0.000 | 3.543/0.000 |
| fast_1100mv_85c | 3.493/0.000 | 0.128/0.000 | 4.474/0.000 | 0.592/0.000 | 3.801/0.000 |
| fast_1100mv_0c | 4.023/0.000 | 0.118/0.000 | 6.054/0.000 | 0.541/0.000 | 3.790/0.000 |

The physical cache write-address fanout and host_wdata D3 setting7 requests were applied. [Fit report](fullrtl100_fanout2/llm_soc.fit.rpt) shows D3_0 or D3_1 setting7 on all32host_wdata inputs; placement chose different row/column I/O paths. Host_wdata no longer has negative hold paths. Hold now fails host_addr20/11/15 by.093/.042/.018ns, with address input D3 setting6. Physical delay settings are demo-backend bindings, not portable RTL or arithmetic/control IP; SDC is unchanged. The device's [programmable-delay capability](https://www.intel.com/programmable/technical-pdfs/683801.pdf) and [QSF assignment form](https://cdrdv2-public.intel.com/654623/an474.pdf) are described separately from this measured implementation.

[Setup](fullrtl100_fanout2/slow_1100mv_85c_setup.rpt) now fails position_q[2] -> attention_acc_q[16],10.070nsdata/8.246nsrouting/four logic levels; all40listed endpoints negative, TNS-62.291ns. The [recommendations](fullrtl100_fanout2/slow_1100mv_85c_recommendations.txt) identify position/equality control duplication. Source currently clears all32S56accumulators in A_EXP_STORE only when time_q==position_q. No accumulator is consumed during score/exponent generation. A portable next fix can clear once in A_QUERY at each head's entry, before scores, removing the position comparator from this wide clear cone without adding state/cycle. This requires all-seven regression and fresh hardware gates; no performance improvement is claimed until verified.

## Fanout1 result: 98.63 MHz, setup/hold FAIL

[Manifest](fullrtl100_fanout1/manifest.json), [source archive](fullrtl100_fanout1/source_archive.json) and [current seven units](../../../tests/full_rtl/evidence/pipeline3_all_units/results.json) match34RTL assets. Quartus Lite25.1std.0 Build1129, CycloneV5CGXFC9E6F35C7, seed1/SPEED/STANDARD; SDC remains10ns with input0.5..2ns/output setup2ns/hold0.5ns and no exceptions. Extraction completed17:28:31 on04Oct2026. Map0errors12warnings, fit0errors4warnings, STA0errors1warning332148. Resources51919ALM/48086FF/1186RAMblocks/9515648bits/186pins; DSP/PLL/DLL/HSSI0. All UCP counts0.18of20checks PASS; application gate rejects98.63MHz.

| Corner1.1V | Setup slack/TNS ns | Hold | Recovery | Removal | Pulse |
|---|---:|---:|---:|---:|---:|
| slow_1100mv_85c | -0.139/-0.268 | -0.102/-0.578 | 2.898/0 | 0.936/0 | 3.600/0 |
| slow_1100mv_0c | 0.112/0 | 0.231/0 | 2.752/0 | 1.219/0 | 3.543/0 |
| fast_1100mv_85c | 3.321/0 | 0.128/0 | 4.537/0 | 0.642/0 | 3.798/0 |
| fast_1100mv_0c | 4.032/0 | 0.115/0 | 6.320/0 | 0.583/0 | 3.788/0 |

[Setup paths](fullrtl100_fanout1/slow_1100mv_85c_setup.rpt) now contain two violations: k_write_address_q[3] to cache request groups7/6, data9.858/9.854ns, zero logic levels;9.243ns routing on the worst path. The preceding vector/cache-enable/scalar failures no longer appear as negative paths in this fit. [Hold](fullrtl100_fanout1/slow_1100mv_85c_hold.rpt) has nine negative endpoints on host_wdata bits14/13/27/6/24/23, including duplicated FFs. Worst-.102ns:3.950ns input data delay versus4.552ns capture-clock delay plus the0.5ns minimum input budget. Fitted input D3_1 setting is6. Recovery/removal pass all corners. Constraints and RTL have not changed; closure remains incomplete.

The archived manifest has STA error/warning totals null because the recorder accepted only plural `warnings`, while the real report says `1 warning`. The raw report/log prove0errors1warning; the immutable manifest is preserved. `tools/timing/test_record.py` verifies the repaired parser against these actual singular/plural reports and rejects incomplete reports. Initial test read failed on a report degree-symbol byte; decoding now matches the recorder's UTF-8 replacement policy. This parser fix changes no timing result.

Quartus is the EDA demonstration backend. Pin standards, physical fanout/delay settings and the chosen device characterize this backend; they do not define ASIC RTL architecture or establish board readiness. No FPGA board bring-up work is required. ASIC migration keeps compute/control RTL and replaces SRAM technology binding plus library/physical constraints; ASIC STA and signoff need actual libraries and SRAM views.

## Release1 result: 91.61 MHz, setup/hold FAIL

[Manifest](fullrtl100_release1/manifest.json), [source archive](fullrtl100_release1/source_archive.json) and [seven-group regression](../../../tests/full_rtl/evidence/pipeline3_all_units/results.json) match the exact34RTL assets. Quartus Lite25.1std.0 Build1129, CycloneV5CGXFC9E6F35C7, seed1/SPEED/STANDARD, unchanged10ns SDC and I/O budgets. A&S0errors/12warnings, fit0errors/4warnings, STA0errors/2timing warnings. Fitted51900ALM/48234FF/1186RAMblocks/9515648bits/186pins; DSP/PLL/DLL/HSSI0. All unconstrained counts0. Extraction completed15:55:47 on04Oct2026. Synthesis and fitting PASS do not imply timing PASS; application remains blocked.

| Corner1.1V | Setup slack/TNS ns | Hold | Recovery | Removal | Pulse |
|---|---:|---:|---:|---:|---:|
| slow_1100mv_85c | -0.916/-3.387 | -0.023/-0.029 | 2.085/0 | 1.423/0 | 3.600/0 |
| slow_1100mv_0c | -0.400/-0.629 | 0.234/0 | 2.482/0 | 1.358/0 | 3.543/0 |
| fast_1100mv_85c | 2.979/0 | 0.129/0 | 4.476/0 | 0.676/0 | 3.799/0 |
| fast_1100mv_0c | 3.931/0 | 0.118/0 | 4.736/0 | 0.616/0 | 3.789/0 |

The standard-FF reset conditioner fixes recovery/removal at every corner. Continuous SIMD payload registers preserve nine-clock response and exact numeric results; all seven synthetic tests PASS with0compile/runtimewarnings, including4229462compute clocks/three selected tokens/16layer executions. This is not trained text generation.

[Worst setup](fullrtl100_release1/slow_1100mv_85c_setup.rpt): write_vector_addr_q[2] to u_vectors/g_request[5]/write_address_q[2],10.624ns data/10.285ns routing/one logic level. Other negative paths are cache write_pending_q[0] to lane write enables, v_address_q to vector groups and scalar_group_q to write_vector_q. [Recommendations](fullrtl100_release1/slow_1100mv_85c_recommendations.txt) identify these paths and control inter-path competition. [Hold](fullrtl100_release1/slow_1100mv_85c_hold.rpt) fails host_wdata21/19 to host_data_q by0.023/0.006ns; Optimize Hold Timing already uses All Paths. Next experiment limits address/cache-mask/scalar driver fanout through FPGA mapping assignments. RTL, transaction latency and constraints stay unchanged; this is a hypothesis until a fresh full fit is measured.

## Explicit2 result: 93.28 MHz, setup/removal FAIL

[Manifest](fullrtl100_explicit2/manifest.json) and [source archive](fullrtl100_explicit2/source_archive.json) identify the exact 33 RTL assets and three configuration files. Quartus Lite25.1std.0 Build1129, CycloneV5CGXFC9E6F35C7, seed1/SPEED/STANDARD and unchanged10ns SDC. Map PASS0errors/12warnings, fit PASS0errors/4warnings, STA completes0errors/2timing warnings. Fitted52189ALM/48316FF/1186RAMblocks/9515648memorybits/186pins; DSP/PLL/DLL/HSSI0. All UCP counts0. [Seven unit groups](../../../tests/full_rtl/evidence/explicit3_all_units/results.json) PASS for this exact source. The application gate correctly rejects Fmax below100MHz; no pretrained application/reference ran.

| Corner1.1V | Setup slack/TNS ns | Hold | Recovery | Removal | Pulse |
|---|---:|---:|---:|---:|---:|
| slow_1100mv_85c | -0.72/-29.655 | 0.249/0.0 | 5.357/0.0 | -0.136/-4.137 | 3.6/0.0 |
| slow_1100mv_0c | -0.234/-2.973 | 0.236/0.0 | 5.386/0.0 | -0.149/-5.29 | 3.543/0.0 |
| fast_1100mv_85c | 3.331/0.0 | 0.131/0.0 | 6.554/0.0 | 0.353/0.0 | 3.799/0.0 |
| fast_1100mv_0c | 4.041/0.0 | 0.12/0.0 | 6.556/0.0 | 0.361/0.0 | 3.789/0.0 |

[Worst setup](fullrtl100_explicit2/slow_1100mv_85c_setup.rpt): `llm_math:u_math|valid_q[0]` to `partial_q[9][2][29]`,10.458ns data delay,9.749ns routing, zero logic levels. [Recommendations](fullrtl100_explicit2/slow_1100mv_85c_recommendations.txt) identify inter-path competition and recommend duplicating this enable. Payload values already have captured operands and a validity pipeline; removing redundant wide payload enables is a portable alternative to technology-specific duplication. Operation acceptance and done latency must stay unchanged and be regressed.

Hold now passes every corner. [Removal](fullrtl100_explicit2/slow_1100mv_0c_removal.rpt) still fails raw reset release to output FFs. An explicit standard-FF reset conditioner with asynchronous assertion and two-edge synchronous release is the next candidate; this is a proposed architectural fix, not timing proof. All paths remain constrained and no false/multicycle exception is added.

## Logic5 result: 99.07 MHz, setup/hold/removal FAIL

`fullrtl100_logic5` is the complete `llm_soc`, built from35 RTL/source assets
at commit `e75166e`, Quartus Lite25.1std.0 Build1129,
Cyclone V `5CGXFC9E6F35C7`, seed1/SPEED/STANDARD. The archived10ns SDC retains
input0.5..2ns/output2ns setup and0.5ns hold, with no timing exceptions.
[Manifest](fullrtl100_logic5/manifest.json), [source ZIP hashes](fullrtl100_logic5/source_archive.json)
and raw reports identify the exact source/configuration. Synthesis PASS0errors/
12warnings and fitting PASS0errors/4warnings do **not** imply timing PASS.
Fitted resources:51986ALM,46834FF,1186M10K,9515648memory bits,186physical pins,
DSP/PLL/DLL/HSSI0. STA completes0errors/2warnings; both332148 warnings report
unmet timing. No trained application or CPU checkpoint reference has run.

| Corner1.1V | Setup slack/TNS ns | Hold slack/TNS ns | Recovery slack/TNS ns | Removal slack/TNS ns | Pulse slack/TNS ns |
|---|---:|---:|---:|---:|---:|
| Slow85°C | −0.094/−0.094 | −0.069/−0.171 | 5.353/0 | −0.138/−4.452 | 3.600/0 |
| Slow0°C | 0.153/0 | 0.233/0 | 5.383/0 | −0.166/−5.485 | 3.543/0 |
| Fast85°C | 3.760/0 | 0.129/0 | 6.559/0 | 0.351/0 | 3.800/0 |
| Fast0°C | 4.024/0 | 0.119/0 | 6.559/0 | 0.357/0 | 3.790/0 |

[Unconstrained counts](fullrtl100_logic5/extracted_unconstrained.rpt) are all0.
[Worst setup](fullrtl100_logic5/slow_1100mv_85c_setup.rpt) is cache address
`k_address_q[3]` → `u_cache|g_request[3].read_address_q[3]`:9.792ns data,
9.188ns routing, zero combinational levels, fanout8 and clock skew−0.202ns.
The route detours across the device; adding arithmetic pipeline stages would
not address this path. [Recommendations](fullrtl100_logic5/slow_1100mv_85c_recommendations.txt)
also identify control-node duplication and score-comparison logic near critical.
[Hold](fullrtl100_logic5/slow_1100mv_85c_hold.rpt) fails on host_addr8/9 and
host_wdata28 inputs. [Removal](fullrtl100_logic5/slow_1100mv_0c_removal.rpt)
fails on reset release to packed output FFs; recovery now passes all corners.

Logic6 completed with exactly the same20slack/TNS checks, resource counts and
99.07MHz FAIL as logic5. Automatic physical FF duplication/high-fanout input
delay optimization did not improve closure. [Logic6 manifest](fullrtl100_logic6/manifest.json)
and [source archive](fullrtl100_logic6/source_archive.json) preserve the full result.

Logic7 added cache-address MAX_FANOUT2 and manual input delay chains. Mapping
inserted logic cells and Fitter created5register duplicates, but all four input
delay assignments were explicitly ignored (Fitter171167). Fmax96.04MHz FAIL;
worst setup op[88] -> lane_round_q[11][0], data10.141ns/skew-.171ns.
The failing hold endpoints moved to host_wdata4/5; reset removal still fails.
[Historical logic7 manifest](fullrtl100_logic7/manifest.json) records all corners.
Its runner rejected the final source-set mismatch after two unused legacy files
were deleted. The original35sources were recovered byte-exact from the preserved
logic6 ZIP. This is historical evidence, with source_hashes_verified=false for
the workspace comparison; it cannot gate the changed current source.

| Corner1.1V | Setup slack/TNS ns | Hold | Recovery | Removal | Pulse |
|---|---:|---:|---:|---:|---:|
| slow_1100mv_85c | -0.412/-3.286 | -0.036/-0.069 | 5.372/0.0 | -0.139/-4.434 | 3.6/0.0 |
| slow_1100mv_0c | -0.024/-0.056 | 0.232/0.0 | 5.401/0.0 | -0.166/-5.479 | 3.543/0.0 |
| fast_1100mv_85c | 3.527/0.0 | 0.128/0.0 | 6.564/0.0 | 0.351/0.0 | 3.799/0.0 |
| fast_1100mv_0c | 4.024/0.0 | 0.119/0.0 | 6.564/0.0 | 0.357/0.0 | 3.789/0.0 |

The completed `fullrtl100_explicit2` uses33sources after structural RTL cleanup,
no synthesizable tasks/unbounded loops, explicit pipeline/LUT ownership. QSF
removes the four ignored delay settings and adds MAX_FANOUT16 on onehot op bits,
targeting the measured control path. SRAM remains the only explicit vendor IP.
SDC/device/seed/I/O budgets are unchanged. [A&S](../synthesis/explicit2/manifest.json)
PASS0errors/12warnings; [all seven units](../../../tests/full_rtl/evidence/explicit3_all_units/results.json)
PASS0compile/runtimewarnings, including the full synthetic graph. Fitting completed, timing FAIL93.28MHz/setup/removal; no current100MHz
PASS is claimed. The preceding explicit1 map was
cancelled after its operator test found a signed buffer-address cast regression.
Its [source/config ZIP](fullrtl100_explicit1/source_archive.json) and
[cancellation](fullrtl100_explicit1/cancellation.json) are retained. The current
candidate explicitly keeps the former unsigned task argument contract.

The12 synthesis warnings include the bounded sigmoid-group input mux index10027,
unused write-A/read-B ports287013, token-output RAM read/write forwarding276020,
and constant pc_debug7 output13024/13410. Existing boundary/protocol/numeric
tests verify the intended behavior; no warning is suppressed. Fitter292013
reports the unavailable LogicLock license; no LogicLock placement is requested.
15714/169085 identify125 automatically located pins because a board pinout was
not supplied.176251/176252 ignore invalid destinations of pc_debug/instr_debug
fast-output wildcards; their constant bits need no FF.56 output FFs were packed.
These reports demonstrate device timing only, not a board implementation.

Actual model25.1 RAM/protocol/selection reruns PASS with0runtimewarnings;
[version-matched evidence](../memory_ip/ram25/results.json) records the official
model source/compiler/library hashes without committing vendor code or cache.
All seven groups and successful hardware gates are still required before application.

## Control1 result:92.75MHz, setup/hold/recovery FAIL

Fresh tag `fullrtl100_control1` records41RTL+3config inputs before compile.
It preserves memory group/IP enable copies at the adapter boundary and appends
four pipeline states for ternary decode, exp difference and scalar clamp flags.
Numeric formulas and expected tokens are unchanged. Ordinary LVDS clock input
buffer feeds direct GCLK; no PLL/DLL/SERDES/ALTLVDS IP. Device5CGXFC9E6F35C7,
seed1/SPEED/STANDARD and10ns/allI/O SDC are unchanged. QSF electrical clock
contract changes to100MHz differential input; fit must record clk/clk(n) pins.
Source hashes/reports must prove any timing improvement. A&S completed08:25:47,
0errors/13warnings; mapDSP/PLL/DLL/HSSI0. Fit0errors/6warnings,31573ALM/42133FF/
1187M10K/9519744memorybits/128pins, DSP/PLL/DLL/HSSI0. STA0errors/2warnings,
but **timingFAIL92.75MHz**. All six units
PASS, including17operators/3460checks/scalar128/clamp128; archived in
[control1 six-group evidence](../../../tests/full_rtl/evidence/control1_six_units/results.json).
Actual-IP full graph started08:41:21, then was cancelled for the measured host
address-owner mux fix; log/cancellation record and six PASS groups retained.
No assertion failure or seven-group acceptance is claimed. No pretrained application has run.

| Corner1.1V | Setup slack/TNS | Hold slack/TNS | Recovery slack/TNS | Removal | Pulse |
|---|---:|---:|---:|---:|---:|
| Slow85°C | −0.769/−28.611ns | −0.152/−0.499ns | −1.288/−7.565ns | 4.156ns | 3.541ns |
| Slow0°C | −0.782/−26.071ns | 0.235/0 | −0.910/−5.311ns | 3.743ns | 3.507ns |
| Fast85°C | 3.094/0 | 0.128/0 | 3.020/0 | 2.317ns | 3.877ns |
| Fast0°C | 3.417/0 | 0.046/0 | 3.421/0 | 1.957ns | 3.872ns |

All otherTNS0; unconstrained0. [Manifest/source archive](fullrtl100_control1/manifest.json)
and52unique report/archive hashes plus commandsSHA verified. [Worst setup](fullrtl100_control1/slow_1100mv_0c_setup.rpt)
is host_rdata31 output: clock6.048ns+data2.634ns vs7.900ns requirement. LVDS input
receiver0.907ns is essentially the same as earlier single-ended0.917ns; the
physical global/IO clock route remains dominant, so the LVDS hypothesis did not
close I/O. PinpairV28/V27,bank5B,GCLK11, no clock IP. [Slow85 setup](fullrtl100_control1/slow_1100mv_85c_setup.rpt)
also shows host_en→parameter address FF13.158ns; raw request drives the address
mux. Since host/core accesses are exclusive, select address by registered core
rd_en and retain raw host cancellation on request/valid controls.
[Recovery](fullrtl100_control1/slow_1100mv_85c_recovery.rpt) fails because reset
data route14ns reaches packed IO FFs. New16406/16469 warning refers to rst_n at
W27→GCLK15 non-dedicated global routing, not clk. Evaluate legal reset pin/global
placement and actual ordinary I/O cell/clock-path delays before next full fit.
Probe measurements are characterization only, never the full graph100MHz gate.
SDC canonical-LF SHA256 remains
`aa4dc1a48cfd2aabd01770a0eb010b14a2abdfe2cfc9d69968a89b1172ccd181`;
Quartus may rewrite CRLF without changing constraints (record.py canonicalizes
config EOL only; RTL hashes remain byte-exact).

## Byte-product result:89.60MHz, setup and hold FAIL

[Bytes1 manifest](fullrtl100_bytes1/manifest.json) archives the exact41RTL/QSF/QPF/SDC
for SIMD9-clock/scalar3-stage products and local parameter payload copies.
A&S0/13,fit0/4,STA0/2;31618ALM/41942registers/1187M10K/0DSP/0PLL. Slow85
setup−1.161ns/TNS−18.601ns, hold−0.085ns/TNS−0.140ns; Slow0setup−0.702ns/
TNS−16.318ns,hold0.234ns. Fast85setup2.790/hold0.129;Fast0setup3.672/hold0.111.
Recovery/removal/pulse allPASS,TNS0;unconstrained0. No100MHz acceptance.
Six unitsPASS, including503math cases/reset9 and17operators/3076checks/scalar128.
Full graph was cancelled for the measured follow-up RTL; its log and cancellation
record are preserved with the six completed groups. No assertion failure or
seven-group acceptance is claimed for bytes1.

The previous scalar/SIMD multiplier and parameter-payload paths no longer lead
the failing list. Worst now: merged KV group_read_enable0→lane31.enable10.919ns;
Quartus recommends duplicate source nodes. Also chunk1→math_b5 highbits10.227ns
(variable ternary selection plus decode), exp_lo→interpolation10.130ns (subtract
plusmultiply), scalar_round48→scalar_group16 (64-bit clamp predicate). Packed
output IO clock/pad setup remains around−0.38ns; host input hold worst−0.085ns.
Preserve group enables within the memory boundary and pipeline the measured
selection/delta/clamp cones. Evaluate a true differential LVDS clock input
buffer with direct GCLK routing; **no PLL or SERDES IP** and unchanged10ns/I/O
budgets. This changes the demo electrical clock contract; physical negative
companion pin must be recorded by the fit report.
[Cyclone V clock pins](https://docs.altera.com/r/docs/683375/current/cyclone-v-device-handbook-volume-1-device-interfaces-and-integration/dedicated-clock-input-pins)
support differential or single-ended clocks; [true LVDS buffers](https://docs.altera.com/r/docs/683375/current/cyclone-v-device-handbook-volume-1-device-interfaces-and-integration/true-lvds-buffers-in-cyclone-v-devices)
exist in row/column IOs. Compiler automatically adds the companion pin per the
[Standard Edition guide](https://docs.altera.com/r/docs/683492/18.1/intel-quartus-prime-standard-edition-user-guide-design-constraints/assigning-differential-pins).
Those are ordinary IO buffers, not an instantiated compute/clock IP. No board
pinout has been supplied; this remains FPGA demo evidence, not board signoff.

## Memory-IP milestone: synthesis/fit PASS, timing FAIL87.49MHz

[Memoryip2 manifest](fullrtl100_memoryip2/manifest.json) records exact41RTL assets,
QPF/QSF/SDC and final Quartus18.1 reports for llm_soc/5CGXFC9E6F35C7.
Explicit altsyncram M10K is isolated behind a replaceable memory adapter.
AUTO_DSP_RECOGNITION OFF and DSP_BLOCK_BALANCING LOGIC ELEMENTS select ordinary
logic cells for compute; no PLL or other vendor compute IP is permitted.
**Fit confirms0DSP/0PLL**,29115ALM/34716registers/1187M10K/9519744memorybits/127pins.
Compared with group2:5229fewer registers,2581more ALMs, same M10K count,
102fewer DSPs; this compares complete configurations, not an isolated RAM benchmark.

| Corner1.1V | Setup slack | Setup TNS | Hold | Recovery | Removal | Pulse |
|---|---:|---:|---:|---:|---:|---:|
| Slow85°C | −1.430ns | −157.190ns | 0.247ns | 4.518ns | 0.765ns | 3.600ns |
| Slow0°C | −1.253ns | −250.719ns | 0.236ns | 4.697ns | 0.635ns | 3.548ns |
| Fast85°C | 2.354ns | 0 | 0.130ns | 6.180ns | 0.735ns | 3.799ns |
| Fast0°C | 3.339ns | 0 | 0.118ns | 6.191ns | 0.730ns | 3.789ns |

All non-setup TNS0 and all unconstrained counts0; worstFmax87.49MHz. STA tool
success is not100MHz timingPASS. [Slow85 paths](fullrtl100_memoryip2/slow_1100mv_85c_setup.rpt)
show parameter lane3 write_data duplicate to lane6 IP request register11.147ns;
[Slow0 paths](fullrtl100_memoryip2/slow_1100mv_0c_setup.rpt) show scalar_a→scalar_product
11.055ns and SIMD input→product10.77ns. Memory payload FF copies are identical
and merge across banks; evaluate preserving local copies at this memory-only
boundary. Pipeline the measured wide scalar/SIMD logic-cell multipliers; do not
add DSP/PLL or relax unchanged10ns SDC. Those follow-up edits are now applied in fullrtl100_bytes1: memory-only
dont_merge write payloads; SIMD byte products/pair sums with9-clock done;
scalar partial/pair/product over3states. Its A&S0/13 reports0DSP/0PLL;
fit completes but timingFAIL89.60MHz; all six unitsPASS, graph later cancelled.
Numeric expected data
remains unchanged; reset coverage grows7→9 and128scalar S128 cases are added.

[A&S evidence](../memory_ip/results.json) records0errors/13warnings. Six287013
warnings are unused data_b/rden_a in generated write-onlyA/read-onlyB models.
276020 preserves small score/output RAM RDW;10027 is a bounded sigmoid subgroup
index0..31;13024/13410 are constant debug pins. Fit0errors/4warnings:292013 optional
LogicLock licence,15714/169085 automatic pins(no board pinout),176251 ignores
constant debug FAST_OUTPUT destinations; all56nonconstant output FFs packed.
STA0errors/2warnings332148 are actual setup failure. All logs retained.
[Memoryip1 failure](fullrtl100_memoryip1/failure.json) preserves unsupported
MAX_DSP_BLOCKS QSF parser errors and exact44assets; memoryip2 removes only that
invalid assignment. Six unitsPASS belong to memoryip2; its graph was cancelled for the measured
timing fixes. Bytes1 sixgroupsPASS, graph cancelled for further measured fixes;
application remains blocked. Earlier102-DSP builds below are historical.

## Full language graph: synthesis và fitting PASS, timing FAIL

[fullrtl100_tiled manifest](fullrtl100_tiled/manifest.json) lưu đúng 38 asset RTL,
QPF/QSF/SDC và report của Quartus Lite18.1, top `llm_soc`, device
`5CGXFC9E6F35C7`, seed1, SPEED/STANDARD FIT. Clock thật10ns, I/O delays và
derived uncertainty dùng [llm_soc.sdc](../../../quartus/llm_soc.sdc); không có
false/multicycle exceptions. Đây là source trước signed-attention fix/pipeline
mới, không phải gate cho source hiện tại.

| Corner 1.1V | Setup slack | Setup TNS | Hold | Recovery | Removal | Pulse |
|---|---:|---:|---:|---:|---:|---:|
| Slow85°C | −3.781ns | −5323.438ns | 0.176ns | 4.999ns | 0.140ns | 3.600ns |
| Slow0°C | −4.202ns | −4791.870ns | 0.055ns | 5.116ns | 0.038ns | 3.548ns |
| Fast85°C | 1.941ns | 0 | 0.103ns | 6.398ns | 0.416ns | 3.798ns |
| Fast0°C | 3.006ns | 0 | 0.037ns | 6.403ns | 0.418ns | 3.787ns |

Worst Fmax **70.41MHz**. Other timing checks have TNS=0; the
[unconstrained summary](fullrtl100_tiled/extracted_unconstrained.rpt) has all
counts zero. STA process success (0 tool errors) does not mean timing PASS;
critical warning332148 confirms the requirement failure.

Fitting completed23:17:26 on01/10/2026: 24125 ALMs, 16132 registers,
9519744 block-memory bits, **1111/1220 RAM blocks**, 104 DSPs. Storage fits.
[Slow0°C setup paths](fullrtl100_tiled/slow_1100mv_0c_setup.rpt) show SIMD
product → `write_vector_q`, data13.531ns; [Slow85°C](fullrtl100_tiled/slow_1100mv_85c_setup.rpt)
shows scalar saturation → vector write, data13.480ns. Quartus
[recommendations](fullrtl100_tiled/slow_1100mv_85c_recommendations.txt) identify
chained adders, long combinational logic and competition/fanout.

Current RTL separates per-lane capture, RNE and saturation, registers scalar
saturation, and only updates the selected linear output lane. Reciprocal is
U25: epsilon42950 gives root≥207 and rounded2³²/root<2²⁵, removing redundant
upper bits on the shared SIMD coefficient path. No numeric or constraint
relaxation. [Pipeline2 manifest](fullrtl100_pipeline2/manifest.json) records
**83.58 MHz, timing FAIL**: Slow85°C setup −1.965ns / TNS −669.972ns;
Slow0°C setup −1.518ns / TNS −258.929ns. Fast setup and all other checks
pass, with zero unconstrained paths. Its fit used 23060 ALMs, 19958 registers,
1111 RAM blocks and 104 DSP blocks.

The new worst paths run from shared KV write addresses to SRAM and from
operator decode to SIMD inputs. The `fullrtl100_local1` snapshot captures requests
per lane, prevents address-register merging inside the SRAM adapter, uses
93 one-hot operator states and captured scalar multiplier operands. It also
fixes masked-token selection at S32_MIN and rejects reserved ternary codes.
[Local1 manifest](fullrtl100_local1/manifest.json) confirms A&S0/6 and fit0/4,
but **timing FAIL84.49MHz**. Slow85°C setup −1.836ns/TNS−952.596ns;
Slow0°C −1.687ns/TNS−260.523ns. Fast setup and all other checks pass;
all unconstrained counts0. Fit22873ALM/23168registers/1187RAMblocks/102DSPs.
That snapshot's worst paths are parameter SRAM→host response11.426ns and
sigmoid interpolation11.472ns, with shared→local KV addresses also failing.
All six units for that snapshot PASS, including the full synthetic graph.
`fullrtl100_pipeline1` preserves the failed sandbox QSYN named-pipe attempt.

Warnings from this actual snapshot: inferred score/output collision pass-through
276020 preserves RTL behavior; constant upper debug pins13024/13410 are
intentional. Fit292013 reports an unavailable optional LogicLock feature;
176251 includes constant pins in fast-output wildcards. I/O15714/169085 records
incomplete board properties and auto-placement of all127 pins. No board pinout
was supplied; this full design uses real constrained I/O, but its pinout is a
core timing demo. These warnings do not establish board compatibility.

## Tree2 and current select revision

[Tree2 manifest](fullrtl100_tree2/manifest.json) records A&S PASS0/6 and fitting
PASS0/29. Timing remains **FAIL91.28MHz** for its exact40RTL assets and unchanged
SDC. Fit24233ALM/34698registers/1220M10K/252MLAB/102DSP; all1220M10Ks are used.

| Corner 1.1V | Setup slack | Setup TNS | Hold | Recovery | Removal | Pulse |
|---|---:|---:|---:|---:|---:|---:|
| Slow85°C | −0.847ns | −158.461ns | 0.215ns | 4.983ns | 0.270ns | 3.600ns |
| Slow0°C | −0.955ns | −58.743ns | 0.087ns | 5.098ns | 0.164ns | 3.548ns |
| Fast85°C | 3.246ns | 0 | 0.125ns | 6.376ns | 0.500ns | 3.801ns |
| Fast0°C | 3.497ns | 0 | 0.060ns | 6.387ns | 0.498ns | 3.790ns |

Other TNS0 and [all unconstrained counts0](fullrtl100_tree2/extracted_unconstrained.rpt).
The [slow setup paths](fullrtl100_tree2/slow_1100mv_85c_setup.rpt) identify variable
lane selection plus RNE/clamp→sigmoid input10.571ns, broad priority-control cones
`op[36]→second_q` and `op[88]→write_vector_q`, and registered output pad delays.
Its [recommendations](fullrtl100_tree2/slow_1100mv_85c_recommendations.txt) call for
shorter combinational logic and reduced fanout/competition.

Six-group exact-source tree2 evidence is [archived here](../../../tests/full_rtl/evidence/tree2_units_final/unit_results.json):
five ModelSim units plus the unchanged compiled Verilator graph, not a pretrained
application. Longer queued writes exposed a final-KV commit error; the retained
failed fixture led to `O_FINISH` waiting for both memory `wr_busy` signals.
Tree1 was cancelled after that failure, not accepted as timing evidence.

Additional tree2 fitter warnings176225/176279 mean low12host response registers
could not pack into I/O due simultaneous clear/load controls. Warning170052
reports uninitialized MLAB power-up behavior, consistent with the adapter's
load-before-read and unreset-payload contract;170056 confirms paused-read
capability. The RAM summary shows automatic shift-register inference also using
memory resources. These are actual mapping choices and must be rechecked after
each fit. STA332148 is a genuine failed timing requirement.

Current select RTL prepares sigmoid RNE4/clamp in parallel, selects lanes through
two registered mux levels, and gives second/write-vector payloads only their
writer-state enables. QSF explicitly selects2.5V/16mA/fast-slew physical output
drivers; clock10ns and input/output constraints are unchanged. This electrical
contract is a core demo without a board pinout or board signal-integrity signoff;
driver options follow the [Cyclone V IOE handbook](https://docs.altera.com/r/docs/683375/current/cyclone-v-device-handbook-volume-1-device-interfaces-and-integration/programmable-ioe-features-in-cyclone-v-devices).
`fullrtl100_select1` preserves a QSF syntax failure, `select2` an interrupted
tool session. `fullrtl100_select3` completed A&S0errors/7warnings and fit0/29;
**timing FAIL92.22MHz**, despite a successful STA tool exit.

| Select3 corner | Setup / setup TNS | Hold | Recovery | Removal | Pulse |
|---|---|---:|---:|---:|---:|
| Slow85 | −0.844ns / −16.608ns | 0.173ns | 6.174ns | 0.776ns | 3.600ns |
| Slow0 | −0.560ns / −13.116ns | 0.040ns | 6.267ns | 0.642ns | 3.548ns |
| Fast85 | 3.060ns / 0 | 0.114ns | 6.983ns | 0.459ns | 3.801ns |
| Fast0 | 3.575ns / 0 | 0.046ns | 6.974ns | 0.412ns | 3.790ns |

[Manifest](fullrtl100_select3/manifest.json) binds the exact40RTL/3configuration
assets, C7 device and unchanged SDC to the archived reports. Other check TNS0;
[unconstrained counts0](fullrtl100_select3/extracted_unconstrained.rpt).
Fit uses25476ALM/35233registers/1220M10K/252MLAB/102DSP/127pins. The new worst
[Slow85 setup path](fullrtl100_select3/slow_1100mv_85c_setup.rpt) is
`scalar_lane_q[9]→write_vector_q[657]`, data10.517ns with32destinations and long
routing. Public host output clear/load and DDIO clock/pad delay also fail setup.
The former sigmoid/control cones are absent from the worst40paths.
[Six-group units](../../../tests/full_rtl/evidence/select3_units/unit_results.json)
PASS for that snapshot, not for later RTL edits.

Candidate `fullrtl100_group1` replaces the scalar broadcast with eight separately
enabled saturation registers, each serving four lanes, and adds an unconditional
public host response register behind the transaction payload. H_DONE preserves
the same ACK/data alignment. QSF disables forced I/O register packing and automatic
shift-register RAM inference; actual SRAM leaves remain inferred memories. It
keeps device `5CGXFC9E6F35C7`, all physical I/O budgets,10ns SDC and seed1.
No capacity-equivalent C6 part is present in the installed Cyclone V device list.

Group1 fails Quartus18.1 inline-genvar syntax; its immutable log/source archive
is retained. Group2 moves the declaration outside loop initialization. Its
[manifest](fullrtl100_group2/manifest.json) verifies exact40RTL/3configuration
hashes and the same C7 device/10ns SDC. A&S0/7,fit0/3,STA0/2 tool exits succeed;
**timing FAIL81.53MHz**, a regression from select3, not closure.

| Group2 corner | Setup / setup TNS | Hold / hold TNS | Recovery | Removal | Pulse |
|---|---|---|---:|---:|---:|
| Slow85 | −2.265ns / −46.475ns | −0.072ns / −0.175ns | 6.179ns | 1.129ns | 3.600ns |
| Slow0 | −2.187ns / −40.230ns | 0.013ns / 0 | 6.270ns | 1.001ns | 3.548ns |
| Fast85 | 2.688ns / 0 | 0.110ns / 0 | 6.985ns | 0.870ns | 3.799ns |
| Fast0 | 2.887ns / 0 | 0.041ns / 0 | 6.975ns | 0.878ns | 3.788ns |

Other check TNS0; [unconstrained counts0](fullrtl100_group2/extracted_unconstrained.rpt).
Fit uses26534ALM/39945registers/1187M10K/0MLAB/102DSP/127pins. Disabling
shift-register RAM inference removes252MLAB/33M10K consumption. Remaining
fit warnings292013/15714/169085 concern optional license and auto-assigned board
pins. No forced-I/O-packing or uninitialized-MLAB warnings remain.

[Worst setup](fullrtl100_group2/slow_1100mv_85c_setup.rpt) is the ordinary LAB
output register `instr_debug[10]→pin`, data5.631ns. The scalar group still routes
across the device (X91→X21),4destinations,data10.605ns; a smaller fanout did not
establish locality. `op[17]→probability_sum_q` also remains a broad control cone.
[Worst hold](fullrtl100_group2/slow_1100mv_85c_hold.rpt) is
`host_addr[24]→host_address_q[24]`,clock skew4.572ns/data4.000ns. Output packing,
clock distribution and local intermediate registers need further design work;
none of these failures may be masked with SDC exceptions.
Five ModelSim groups PASS for current source; the independent unchanged graph
continues, with automatic exact-hash evidence aggregation after completion.
Pretrained application remains blocked.

## Legacy timing evidence

## Report người dùng đã chạy

Snapshot gốc được giữ trong [user_baseline](user_baseline/manifest.json), gồm [Fitter summary](user_baseline/matmul_free.fit.summary), [Timing Analyzer summary](user_baseline/matmul_free.sta.summary) và report chi tiết. Khi chạy, project chưa có SDC: Quartus tự tạo `clk` với chu kỳ **1 ns**. [Constraint đã trích xuất](user_baseline/extracted_sdc.rpt) và [check_timing](user_baseline/extracted_checks.rpt) xác nhận **67 input và 59 output thiếu delay constraint**.

| Corner | Fmax `clk` | Setup slack, clock tự tạo 1 ns | Data delay của path xấu nhất |
|---|---:|---:|---:|
| Slow 1,1 V, 0 °C | [24,86 MHz](user_baseline/slow_1100mv_0c_fmax.rpt) | −39,221 ns | 39,952 ns |
| Slow 1,1 V, 85 °C | [25,11 MHz](user_baseline/slow_1100mv_85c_fmax.rpt) | −38,832 ns | 39,550 ns |

Ở corner Slow 0 °C, [setup path chi tiết](user_baseline/slow_1100mv_0c_setup.rpt) đi từ `rowwise_dispatch:u_row|rowwise_op:u_alu|element_index_q[2]` đến `result_word[87]`, qua **25 logic levels**. Chọn lane từ word 256 bit, chọn operand, nhân, cộng REC, dịch/RNE, saturation và chọn vị trí ghi kết quả nằm trên cùng đường tổ hợp. Nhiều path xấu khác có cùng nguồn chọn lane.

Fmax là ước lượng giới hạn cho các path cùng clock được công cụ xét. Nó không thay thế setup/hold của host, recovery/removal của reset hoặc kiểm tra mọi corner. Slack âm với clock tự tạo 1 ns không có nghĩa thiết kế được yêu cầu chạy 1 GHz. Thiếu I/O constraint khiến report cũ chưa đánh giá đầy đủ giao tiếp bên ngoài.

## Constraint cho phép so sánh

[matmul_free.sdc](../../../quartus/matmul_free.sdc) tạo clock **20 ns / 50 MHz**, dùng clock uncertainty do Quartus suy ra và ghi rõ giả định giao tiếp đồng bộ:

| Giao tiếp ngoài | Budget demo |
|---|---|
| Input, gồm thời điểm nhả `rst_n` | đến 0,5…2,0 ns sau cạnh clock |
| Output | setup bên nhận 2,0 ns; hold 0,5 ns |

Không có false-path hoặc multicycle exception để ẩn path chức năng. Các budget là giả định cho demo core; khi ghép board hoặc ASIC phải thay bằng contract thật của clock/reset/host.

Baseline có constraint và bản RTL tối ưu phải dùng cùng device, các assignment QSF tương ứng, SDC, seed và effort. Thay constraint có thể thay placement/routing; vì vậy không lấy chênh lệch với bản tự tạo 1 ns làm bằng chứng riêng cho cải tiến RTL. Manifest của từng snapshot gắn hash source, constraint và report với kết quả.

## Các snapshot đã đo

| Snapshot, cùng SDC 20 ns/seed 1 | Fmax thấp nhất | Setup slack thấp nhất | Critical path setup thấp nhất |
|---|---:|---:|---|
| [RTL cũ, baseline có constraint](constrained_baseline/manifest.json) | 25,10 MHz | −19,840 ns | Rowwise index → result word; 39,572 ns ở Slow 0 °C |
| [Tách register trong datapath](optimized/manifest.json) | 36,15 MHz | −7,665 ns | host_addr[30] → host_rdata[28]; 23,565 ns ở Slow 85 °C |

Baseline post-fit hoàn tất 13:56:55, STA 14:01:26 ngày 01/10/2026. Baseline không còn input/output setup/hold path thiếu constraint: xem [unconstrained](constrained_baseline/extracted_unconstrained.rpt) và [check_timing](constrained_baseline/extracted_checks.rpt). Hold, recovery/removal và pulse width đều dương. `virtual_clock=1` trong check_timing báo không có clock ảo; demo chủ ý tham chiếu host tới `clk` thật.

Lượt tách datapath hoàn tất STA lúc 14:14:18. Critical path đã chuyển từ rowwise sang host read; ở lượt này target **50 MHz chưa đạt**, nên không coi tăng Fmax là timing closure. [Setup path](optimized/slow_1100mv_85c_setup.rpt) và [recommendations](optimized/slow_1100mv_85c_recommendations.txt) là đầu vào cho bước tối ưu tiếp theo.

Hai lượt đầu được tạo từ snapshot RTL thủ công; manifest xác nhận source hashes nhưng ghi `configuration_hashes_verified=false` vì chưa có hash configuration trước compile. QSF/SDC thực tế được archive với report, và cùng constraint/seed được đối chiếu; không bổ sung provenance giả sau khi chạy. Runner timing lưu cả configuration trước compile cho các lần tái lập tiếp theo.

## Gợi ý của Quartus và hướng sửa RTL

[Recommendations của baseline Slow 0 °C](user_baseline/slow_1100mv_0c_recommendations.txt) chỉ ra:

| Gợi ý | Thay đổi cấu trúc cần đánh giá |
|---|---|
| Long Combinational Path | Chốt operand, product, raw result và rounded result để chia đường dài |
| Chained Adders | Tách cộng REC/sign correction khỏi multiplier và khỏi RNE/saturation |
| DSP Register Packing | Đặt thanh ghi cạnh input/output multiplier bằng RTL SystemVerilog chung |
| Inter-path Competition | Giảm việc `element_index_q` lái đồng thời mux đọc, số học và mux ghi |

Việc thêm register giữ nguyên phép tính số nguyên, rounding và saturation, nhưng tăng số chu kỳ xử lý word. `rowwise_dispatch` đã chờ `busy/done`, nên thay đổi latency được kiểm tra qua handshake và model demo. Hai multiplier 16×16 tiếp tục dùng chung cho MUL và REC; không thêm primitive, macro synthesis hoặc thuộc tính chỉ dành cho Quartus.

NORM tách capture operand, multiply, RNE và xử lý kết quả bằng cùng kiểu register. P1 thêm hai chu kỳ mỗi pair; P2/P3 thêm ba chu kỳ mỗi pair, tổng overhead **8 × ceil(K/2)** chu kỳ/NORM. `sum_sq`, mean-square, hệ số, clamp, absmax và packing không đổi. Hai multiplier S25×S25 và hai đường RNE tiếp tục dùng chung giữa ba pass.

Postscale của ternary engine chốt tích S42, RNE S42 rồi cộng bias S43/saturation/pack: thêm hai clock mỗi output row. `rne_shift42` giữ RNE bit-exact với reference rộng ở shift 0…63; shift≥42 trả zero. Module finish được dùng chung với wrapper tổ hợp, không tạo implementation chỉ dành cho timing demo. Compose dùng signed S7 cho hiệu hai shift U6, không đổi latency.

Lượt tiếp theo chốt host read address/region và response data/tag, tách đường address → mux → output; control/descriptor read hai cạnh lên, SRAM/imem bốn cạnh lên, write vẫn trực tiếp. NORM dùng lại `norm_r`, `quant_r`, `quant_d` đã chốt ở PREP khi launch divider và làm tròn hệ số, không thêm chu kỳ. [Host contract](../../design/interfaces.md#host-32-bit) quy định response giữ snapshot đầu và cách poll status mới.

| Rowwise word có `n` phần tử hữu ích | Từ cạnh nhận start đến cạnh done |
|---|---:|
| ADD/SUB/MUL/RELU | `5 × ceil(n/2)` clock |
| REC | `5 × n` clock |
| SIG | `6 × n` clock |

Các batch đi lần lượt; đây không phải pipeline cho phép nhận batch mới mỗi clock. Hai output số học cần năm clock, một REC cần năm clock. SIG thêm một clock mỗi word so với bản trước: LOAD dùng phần lớn khoảng trống giữa hai lần sigmoid done/start. Chu kỳ model còn gồm đọc/ghi SRAM, scalar, fetch và scheduler. Fmax tăng không tự chứng minh throughput model tăng.

## Chạy lại và đọc kết quả

Chạy full compile sau khi sửa RTL hoặc constraint; Ctrl+K chỉ chạy Analysis & Synthesis, chưa tạo kết quả timing sau placement/routing:

```powershell
Push-Location quartus
try {
    quartus_sh --flow compile matmul_free
} finally {
    Pop-Location
}
quartus_sta -t tools/timing/extract.tcl docs/verification/timing/constrained sdc
```

[Hướng dẫn extractor](../../../tools/timing/README.md) giải thích chọn project baseline và xuất 40 setup/hold paths cho bốn corner. Đọc Fmax cùng setup, hold, recovery/removal, pulse width, unconstrained paths và recommendations. Kiểm tra hash source của report với [regression](../../../tests/results.json); dùng [model demo](../../demos/README.md) để đo ảnh hưởng số chu kỳ inference.

---

[Về verification](../README.md) · [Rowwise RTL](../../source_guide/blocks/rowwise_op.sv.md) · [Design review](../../reviews/design_review.md)
## Current verification scope

Portable bit-product arithmetic, ordinary registers/control and replaceable
SRAM binding remain the implementation policy. The preceding35-source graph
unit PASS is archived in [logic6q5](../../../tests/full_rtl/evidence/logic6q5_all_units/results.json).
The current34-source snapshot has all-seven PASS and release1 timing FAIL91.61MHz; fresh physical closure is required.
See [checkpoint](../../../TASK_STATE.md) for active jobs and reproduction commands.
