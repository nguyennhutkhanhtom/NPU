# Rà soát design và thống nhất RTL ngày 01/10/2026

<!-- reading-navigation:start -->
[Documentation](../../README.md) → [Archive](../../archive/README.md) → This page

| Reading guide | Document |
|---|---|
| Read first | [Historical context](../../archive/README.md) |
| Continue / related lookup | [Current evidence](../../verification/optimization_status.md) |
<!-- reading-navigation:end -->

> **Category: HISTORICAL SNAPSHOT — see dated checkpoints below.** This snapshot must not determine current architecture, live status or active tasks.

Báo cáo này ghi core `matmulfree` và các snapshot trước. Rà soát top ngôn ngữ
hiện tại nằm ở [full RTL design](<../../design/full_rtl_language.md>),
[timing evidence](<../../verification/timing/README.md>) và [checkpoint](<../../../TASK_STATE.md>).

<details>
<summary>Mục lục trang</summary>

- [Implementation hiện hành](#implementation-hiện-hành)
- [Tối ưu từ timing report](#tối-ưu-từ-timing-report)
- [Các khối đã rà soát](#các-khối-đã-rà-soát)
- [Kiểm chứng bản RTL thống nhất](#kiểm-chứng-bản-rtl-thống-nhất)
- [Kiểm chứng lịch sử trước khi bỏ macro](#kiểm-chứng-lịch-sử-trước-khi-bỏ-macro)
- [Phạm vi còn lại](#phạm-vi-còn-lại)

</details>

Đã kiểm tra hierarchy từ `matmulfree`, package số học, scheduler/PC, descriptor, memory wrapper và từng engine. Các tối ưu NORM, RNE, địa chỉ weight và instruction memory được giữ. Core dùng **một implementation cho mô phỏng và synthesis**, không chọn logic theo `SYNTHESIS`/`QUARTUS_SYNTHESIS` hoặc thuộc tính riêng của Intel. Quartus dùng để demo tổng hợp và timing FPGA của RTL; các report timing được tập hợp trong [timing hub](<../../verification/timing/README.md>).

## Implementation hiện hành

| Khối | Thay đổi | Hợp đồng / ảnh hưởng |
|---|---|---|
| NORM | Mux operand theo P1/P2/P3; dùng chung hai multiplier S25×S25 và hai đường RNE, chốt operand/product/rounded result | Thêm 2 chu kỳ/pair ở P1, 3 ở P2 và P3; công thức, scratch packing và tail giữ nguyên |
| RNE trong package | Arithmetic shift tạo thương floor, guard/sticky chọn cộng một | Giữ ties-to-even cho âm/dương, S64 min/max và shift=0..63; hàm tổ hợp gán đủ mọi biến |
| Ternary address | Pointer row weight tăng stride 1..4; bounds extent dùng shift/add với trung gian U12 | Bỏ phép nhân tạo địa chỉ; không thêm chu kỳ |
| SRAM parameter/workspace | Tám bank 32 bit, whole-word write/enable theo lane, một cổng đọc synchronous chung cho host/compute | Một handshake cho mọi build; không có `ramstyle`, `M10K` hoặc primitive FPGA |
| Host read frontend | Chốt address/one-hot region và response/data/tag; mux response song song | Control/descriptor hai cạnh lên, SRAM/imem bốn; writes trực tiếp; poll cùng địa chỉ cần idle một cạnh |
| Instruction memory + scheduler | Một cổng synchronous chung cho host/fetch, request/response tags và valid; S_FETCH chờ dữ liệu | Cùng fetch/host latency trong mọi build; RAM/read data không async reset |
| Sigmoid | Luôn dùng ROM `case` hằng từ `sigmoid_lut.svh` | Không có `LUT_FILE`/`SIG_LUT_FILE`, `$readmemh` hoặc file override lúc chạy |
| Kiểm tra giao tiếp | Kiểm tra misuse/handshake ở testbench | RTL không cần nhánh loại bỏ assertion khi synthesis |
| Căn bậc hai | Radix-4 đọc hai bit radicand mỗi bước; root U32, remainder U34, một subtractor U35 dùng chung cho compare/update | Vẫn floor-sqrt U64 và 32 bước xử lý, giảm datapath/state so với thuật toán bitmask U64 |
| Divider NORM | Numerator/quotient U55, denominator/remainder U32 | Giảm chín bước chia mỗi lần; giữ mean-square U64/F32, epsilon U65 và kết quả hệ số |
| Scale compose | Fit filter RNE chính xác trước divider U48/U25 | Chỉ chia tối đa một lần; giữ cặp M/r lớn nhất có thể biểu diễn, không thử chia cho từng candidate quá lớn |
| Ternary postscale | Chốt product S42 và RNE S42 trước postscale_finish bias/S43/saturation | Thêm hai clock/output row; interface postscale tổ hợp vẫn dùng chung finish để kiểm chứng |
| Rowwise | Hai multiplier và hai đường scale/RNE; chốt operand/product/raw/rounded result để chia đường tổ hợp | REC cộng hai tích trước một lần RNE; latency word tăng, dispatcher vẫn chờ busy/done |
| Sigmoid datapath | Coordinate S45, slope U10, product U34 | Giữ 24 fractional bits, LUT và output; kiểm tra toàn bộ F_t=0..24 |
| Metadata scale | Chỉ reset q_valid; payload D/base/length 336 bit ghi đầy đủ bằng enable riêng cho tám slot, index hằng | Dữ liệu invalid không được đọc; mô tả FF có parallel reads, không phụ thuộc RAM read-during-write |
| Guard/status | TM tĩnh từ chối mọi overlap với q metadata hợp lệ; NORM bị reject mask overflow cũ | Chặn bypass bằng alias ID và tránh báo lại trạng thái của request trước |

**Hợp đồng host:** read request và response được chốt tại top; control/descriptor read hai cạnh lên, SRAM/imem read bốn cạnh lên. Host giữ enable/read/address đến ready; đọc lại status cùng địa chỉ cần idle qua một cạnh clock để lấy snapshot mới. Write vẫn trực tiếp. Backend adapter read/tag/valid giữ hai cạnh lên, scheduler fetch không đổi. Reset hủy request/response, mask payload và giữ RAM. [Interface](<../../design/legacy/interfaces.md#host-32-bit>) ghi contract đầy đủ.

`sram_256_wrapper` là adapter RTL chung để bind SRAM macro. Macro PDK phải đáp ứng cổng, mask ghi và latency của adapter; nếu khác, cần điều chỉnh adapter và kiểm chứng giao tiếp. Block RAM của FPGA không phải ràng buộc kiến trúc của core.

## Tối ưu từ timing report

Report người dùng ở corner Slow 1,1 V/0 °C cho Fmax **24,86 MHz**. Critical path `element_index_q[2]` → `result_word[87]` trong rowwise đi qua **39,952 ns / 25 logic levels**. Project lúc đó chưa có SDC; clock tự tạo 1 ns và host/reset chưa có I/O delay. [Timing hub](<../../verification/timing/README.md>) giữ report gốc và giải thích constraint dùng cho phép so sánh có kiểm soát.

Rowwise tách chọn lane/magnitude, hai phép nhân, sign correction/tổng REC, RNE và saturation/pack bằng các register. Mỗi batch đi qua LOAD → MULTIPLY → RAW → ROUND → PACK; ADD/SUB/MUL/RELU xử lý hai phần tử, REC xử lý một state. SIG chốt lane trước khi gọi sigmoid và giữ handshake. Payload số học không reset; FSM/enable bảo đảm dữ liệu chỉ được dùng sau khi ghi. Reset hủy giao dịch và xóa trạng thái/output như trước.

NORM cũng chốt operand S25, product S48 và kết quả RNE S64 để tách mux đọc khỏi multiplier, RNE và absmax. P1 đi qua CAPTURE → MUL → PROC; P2/P3 đi qua CAPTURE → MUL → ROUND → PROC. So với bản trước, toàn NORM thêm **8 × ceil(K/2) chu kỳ**, chưa tính các bước đọc/ghi và scalar vốn đã có. Hai multiplier/RNE tiếp tục dùng chung; payload mới có enable theo pass, không async reset.

Ternary postscale chia thành SCALE_PRODUCT → SCALE_ROUND → SCALE: tích và RNE giữ S42, cộng bias S32 trong S43 rồi clamp/pack. Hàm `rne_shift42` có RNE đúng với mọi shift U6; shift≥42 trả zero, gồm tie −0,5 tại S42 min. `postscale_finish` được dùng chung bởi engine registered và wrapper tổ hợp. Compose chỉ thu gọn hiệu hai shift U6 xuống signed S7, giữ phép tính và số chu kỳ.

Lượt đầu chuyển critical path sang `host_addr → host_rdata`. Lượt tiếp theo chốt request/response host, dùng mux region one-hot thay priority chain; NORM DIV_START/RNE hệ số dùng lại norm_r/quant_r/quant_d từ PREP, không thêm chu kỳ. Các thay đổi này được kiểm tra cùng model demo sau khi chỉnh RTL.

Đây là thay đổi cấu trúc RTL dùng chung cho simulation/synthesis. Không thay công thức REC, rounding, saturation, descriptor hoặc ISA; không dùng false-path/multicycle để bỏ critical path. Thêm register tăng số chu kỳ; phép đo model và timing phải dùng cùng snapshot để đánh giá ảnh hưởng thực tế.

### Biên số học cho các độ rộng mới

- **Sqrt:** trước mỗi bước, prefix đã xử lý bằng `root² + remainder` và `0 ≤ remainder ≤ 2×root`. Trước bước cuối root <2³¹, nên ghép thêm hai bit vào remainder cần U34. Trial `4×root+1` cũng U34; bit bổ sung của phép trừ U35 phát hiện borrow.
- **NORM U55:** rms U32 dẫn tới norm_r≤22, numerator `2^(32+norm_r)` có bit cao nhất là 54. ΣX² cần U40; fractional mean cần U41; numerator QUANT cần tối đa U48. Chỉ thu gọn divider, không cắt radicand/epsilon.
- **Compose:** U24 max là số lẻ nên tie tại U24max+0,5 làm tròn lên giá trị không hợp lệ. Fit phải dùng `< (2²⁴−0,5)×denominator`; với denominator `127× 65536`, limit là `0x7EFF_FFC0_8000`. Sau lọc, shift được chọn ≥−2, numerator nằm trong U48 và denominator tối đa `127× 65536×4` nằm trong U25. Guard từ chối shift<−2 trước khi launch. Ví dụ M=4096, D=65536, r=0 giữ M_out=8454660/r_out=18, giảm từ 18 lần chia 64 bước xuống một lần chia 48 bước (ước tính giảm 1.138 clock).
- **Sigmoid:** tọa độ `x_raw×2^(28−F_t)+128×2²⁴` nằm trong S45 cho toàn bộ S16, F_t=0..24. Chênh hai mẫu cố định ≤512 cần U10; tích với fraction U24 được giữ trong U34. Tooling kiểm tra bound của LUT trước build.

## Các khối đã rà soát

| Nhóm | Nội dung kiểm tra / quyết định |
|---|---|
| Host, scheduler, PC | Decode window/alignment, read valid, host bị chặn khi running, chốt instruction, restart, HALT/error và không wrap PC |
| Descriptor / scale metadata | Descriptor reset đủ; scale payload chỉ hợp lệ sau full write, reset valid, length/format/bounds, invalidate khi q hoặc descriptor bị sửa; static TM kiểm tra mọi extent q hợp lệ |
| Parameter / workspace SRAM | Tám bank 32 bit, whole-word write/mask lane, không async reset RAM/read data, response đúng client/address/lane |
| NORM + scalar | Tổng U40, epsilon intermediate U65, divider/căn, hệ số U24/U6, S24 scratch, absmax, tail, clamp; ba pass độc quyền cho phép dùng chung datapath |
| Ternary / reduction / postscale | Mã weight, mở rộng S9 trước đổi dấu, cây cộng cân bằng, ACC18 với K≤512, stride/tail, bias/no_bias, packing S16/S32 và extent không wrap |
| Rowwise / dispatch | Scale và signedness, ADD/SUB/MUL, gate U16, REC chỉ một lần RNE, ReLU, tail/overlap; hai multiplier và hai scale/RNE paths dùng chung |
| Sigmoid / LUT | 257 mẫu, grid S45, slope U10, product U34, 24 fractional bits, RNE trên giá trị đầy đủ; một ROM hằng cho mọi build |
| Scale compose | Tích U48, fit filter với strict tie, divider 48/25, exact M/r và lỗi metadata; giữ instance riêng để không thay protocol engine |
| Helper / legacy / board wrapper | Phân biệt module được instantiate; compile toàn source. Không đưa pipeline legacy hoặc EXP stub vào scheduler hiện hành |

## Kiểm chứng bản RTL thống nhất

`./tests/run.ps1 -Block All` pass **10 mục kiểm tra** lúc **14:31:18 ngày 01/10/2026**: một mục xác minh ROM và chín testbench RTL. Compile toàn source: **0 error / 0 warning**. Không có `-Mode` hoặc macro chọn implementation; kết quả/source/test hashes tại [tests/results.json](<../../../tests/results.json>).

- **168 ca host / 23.827 commands**: NORM 43, ternary 65, rowwise 57, host/PC 3. Thêm **30 protocol reads / 11 cancellations / 4 running-blocked regions** kiểm tra frontend host; overflow→NORM bị reject không reset, reset giữa NORM divider rồi restart, alias q cùng vùng/partial overlap và exact-end không overlap.
- **1.800 ca rowwise độc lập / 13.260 phần tử**, reference S128; 42.843 lần thay input khi busy và reset tại sáu pha. Kiểm tra output/cờ bit-exact, không nhận start khi busy, tail zero và timing accepted-start/done sau khi tách register.
- **37.189 RNE**, 106 divider U64, **4.301 sqrt U64** (toàn bộ 0..4095, square±1, U64 max), **900 exact compose M/r** với reference U128 độc lập. Compose tối đa **99 clock** trong tập kiểm tra, giới hạn test 128; gồm strict tie, reset/input latching và start khi busy.
- **5 divider width profiles / 2.320 checks**: 1/1, 7/3, 3/7, 64/32, 64/64. **12.720 postscale** với biên accumulator, M/r, bias và bão hòa S16/S32.
- **1.638.400 sigmoid inputs**, toàn bộ S16 ở **25 F_t=0..24**, cùng reset và busy-start. Arithmetic: 3.242 addsub, 4.452 mul, 5 accumulator profiles. Instruction memory **1.027**, SRAM **47 checks**; các monitor arbitration đều pass.
- Tooling kiểm tra đủ **257 mẫu**, monotonicity, adjacent delta≤512, symmetry/RNE và từ chối **hai asset thiếu + hai asset hỏng**. Core không nạp/override LUT lúc chạy.

Snapshot trước tối ưu timing: Quartus Analysis & Synthesis demo thành công lúc **11:24:04 ngày 01/10/2026**, **0 error / 0 warning**, không define macro chọn implementation và không có thuộc tính memory riêng trong core. Quartus Lite 18.1, Cyclone V `5CGXFC7C7F23C8`, top `matmulfree`, effort AUTO, tối ưu AREA. Các số dưới đây là synthesis estimate của snapshot đó; [timing hub](<../../verification/timing/README.md>) ghi kết quả post-fit riêng. Chưa có PPA ASIC.

| Chỉ số trong demo Quartus | Trước đợt rà soát này, 01:51 | Sau rà soát, 11:24 |
|---|---:|---:|
| Dedicated logic registers | 6.712 | 6.497 |
| Combinational ALUTs | 12.306 | 11.798 |
| Logic cells sau synthesis | 18.135 | 17.369 |
| Estimate ALMs needed | 8.441 | 8.005 |
| DSP blocks | 7 | 7 |
| Block memory bits | 334.336 | 334.336 |
| Error / warning | 0 / 0 | 0 / 0 |

Sqrt riêng giảm từ 200 xuống 168 FF và 301 xuống 51 ALUT trong demo. Toàn chip giảm 215 FF và 508 ALUT. Metadata vẫn là FF, bỏ reset 336 payload bits; không tính giảm reset như giảm số FF. Các số liệu là mapping FPGA, không xác nhận timing, power hoặc diện tích ASIC. Report: [synthesis](<../../verification/reports/quartus_synthesis.rpt>), [summary](<../../verification/reports/quartus_synthesis.summary>), [phân tích warnings](<../../verification/README.md>).

## Kiểm chứng lịch sử trước khi bỏ macro

Suite cũ pass 19 lượt lúc 01:17:21 ngày 01/10 trên ba cấu hình thường/`SYNTHESIS`/`SYNTHESIS + QUARTUS_SYNTHESIS`. Test file override và hai test LUT sai/thiếu trong suite đó thuộc interface cũ. Kiểm tra cấu trúc riêng lúc 01:23:09 xác nhận descriptor 1.024 FF, không latch; workspace SRAM 65.536 bit block RAM; instruction 6.656 bit block RAM / 22 FF. Các kết quả này là lịch sử, không thay thế regression của implementation thống nhất ở trên.

## Phạm vi còn lại

Đã chạy [checkpoint Binary-MNIST160](<../../demos/legacy/mnist.md>) bằng CPU gốc/reference số nguyên/RTL: 10/10 ảnh mẫu đúng và 40 lượt tầng bit-exact. [Demo NanoFable](<../../demos/language.md>) bổ sung generation CPU (3 prompt × 32 token, deterministic repeat) và 168 lượt linear ternary thực trên RTL, 33.792 output S32 bit-exact. Từng báo cáo model ghi snapshot và số chu kỳ tương ứng. Toàn graph ngôn ngữ và các operator còn thiếu vẫn ở CPU. Chưa có accuracy toàn bộ MNIST, đánh giá chất lượng hội thoại, PPA/STA ASIC hoặc SRAM PDK. Các engine vẫn có multiplier riêng: rowwise gồm cả sigmoid, NORM, ternary postscale và scale compose. Dùng chung đúng hai multiplier toàn chip cần đổi kiến trúc cấp phát tài nguyên và lịch chạy; kết quả hiện tại xác nhận tối ưu trong từng khối và demo FPGA.

---

[Xem verification và report](<../../verification/README.md>) · [Các demo](<../../demos/README.md>) · [Về mục lục tài liệu](<../../README.md>)
