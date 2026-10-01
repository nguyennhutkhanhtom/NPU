# Timing FPGA và tối ưu critical path

[Project](../../../README.md) → [Tài liệu](../../README.md) → [Verification](../README.md) → **Timing**

Trang này ghi cách đọc report post-fit, constraints và thay đổi RTL dựa trên critical path. Phần full graph dùng Cyclone V C9; các snapshot legacy bên dưới dùng thiết bị riêng được ghi trong manifest. Các phép đo là FPGA demo, chưa xác nhận ASIC signoff.

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
operator decode to SIMD inputs. Current `fullrtl100_local1` captures requests
per lane, prevents address-register merging inside the SRAM adapter, uses
93 one-hot operator states and captured scalar multiplier operands. It also
fixes masked-token selection at S32_MIN and rejects reserved ternary codes.
[Local1 manifest](fullrtl100_local1/manifest.json) confirms A&S0/6 and fit0/4,
but **timing FAIL84.49MHz**. Slow85°C setup −1.836ns/TNS−952.596ns;
Slow0°C −1.687ns/TNS−260.523ns. Fast setup and all other checks pass;
all unconstrained counts0. Fit22873ALM/23168registers/1187RAMblocks/102DSPs.
The current worst paths are parameter SRAM→host response11.426ns and
sigmoid interpolation11.472ns, with shared→local KV addresses also failing.
All six current-source unit groups PASS, including the full synthetic graph.
`fullrtl100_pipeline1` preserves the failed sandbox QSYN named-pipe attempt.

Warnings from this actual snapshot: inferred score/output collision pass-through
276020 preserves RTL behavior; constant upper debug pins13024/13410 are
intentional. Fit292013 reports an unavailable optional LogicLock feature;
176251 includes constant pins in fast-output wildcards. I/O15714/169085 records
incomplete board properties and auto-placement of all127 pins. No board pinout
was supplied; this full design uses real constrained I/O, but its pinout is a
core timing demo. These warnings do not establish board compatibility.

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
