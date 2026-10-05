# Tài liệu NPU ternary

[Trang project](../README.md) → **Tài liệu**

Đây là điểm bắt đầu cho bản RTL hiện hành. Tài liệu được chia theo việc cần làm: hiểu thiết kế, lập trình qua host, đọc code, kiểm chứng, chạy model và tra cứu lịch sử. Source đang phát triển nằm trong [Verilog Source code](<../Verilog Source code/README.md>).

## Đọc theo thứ tự

**[Toàn graph hiện tại](design/full_rtl_language.md) → [Host, tests và application](../tests/full_rtl/README.md) → [Từng khối RTL](source_guide/blocks/README.md) → [Timing post-fit](verification/timing/README.md) → [Demo model](demos/README.md)**

Core instruction-driven trước được mô tả riêng tại [kiến trúc legacy](design/architecture.md),
[ISA/host legacy](design/interfaces.md) và [hierarchy legacy](source_guide/README.md).

| Bạn muốn làm gì? | Bắt đầu ở đây | Đọc tiếp |
|---|---|---|
| Hiểu toàn graph sinh token trên RTL | [Autonomous language graph](design/full_rtl_language.md) | [Host, numeric và gate tests](../tests/full_rtl/README.md) |
| Nạp parameter/config/prompt cho top hiện tại | [Host và memory map toàn graph](design/full_rtl_language.md) | [Gated application runner](../tests/full_rtl/README.md) |
| Tra cứu core 32 PE và chương trình legacy | [Kiến trúc và bảng bit](design/architecture.md) | [Instruction, descriptor và host](design/interfaces.md) |
| Sửa một module RTL | [Mục lục từng file](source_guide/blocks/README.md) | [Các cải tiến và hợp đồng hiện hành](reviews/design_review.md) |
| Xem tối ưu mới nhất và evidence hiện tại | [Review version 3](reviews/rtl_change_review_v3.md) | [Trạng thái và lệnh tái hiện](verification/optimization_status.md) |
| Tra cứu nghiên cứu kiến trúc | [Architecture research](design/architecture_research.md) | [Mục lục review](reviews/README.md) |
| Chuyển sang ASIC và kiểm tra policy IP | [ASIC portability](design/asic_portability.md) | [Cây nhân bit](source_guide/blocks/logic_mul.sv.md), [SRAM binding](source_guide/blocks/quartus_word_ram.sv.md) |
| Thay SRAM technology leaf và kiểm tra bộ nhớ nhỏ | [ASIC memory binding](design/asic_memory_binding.md) | [Elaboration không nạp vendor RAM](verification/portable_elaboration_cache1/results.json) |
| Kiểm tra coding style RTL | [Explicit RTL và register ownership](design/rtl_style.md) | [Repository rules](../AGENTS.md) |
| Chạy test, xem synthesis hoặc timing | [Regression và demo synthesis](verification/README.md) | [Critical path và Fmax post-fit](verification/timing/README.md) |
| Chạy model có checkpoint | [Full RTL application](../tests/full_rtl/README.md) | [Model candidates](demos/candidates.md), [asset setup NanoFable](../tests/language_demo/README.md) |
| Tra cứu các quyết định và lỗi cũ | [Báo cáo tích hợp](reviews/implementation_review.md) | [Lịch sử, thesis và bài báo](history/README.md) |

## Tổ chức tài liệu

```text
docs/
├── README.md                 ← mục lục này
├── design/                   ← kiến trúc, bit-width, ISA và host contract
├── source_guide/              ← hierarchy, chú giải từng RTL, hash và validator
├── verification/             ← regression, synthesis, timing post-fit và report
├── demos/                    ← model candidates và các demo đã thực hiện
├── reviews/                  ← sửa lỗi, cải tiến và phạm vi đã kiểm tra
└── history/                  ← archive, cleanup manifest, thesis và tài liệu gốc
```

Mỗi nội dung có một trang chính; README trong source dẫn về tài liệu interface. Các trang đều có đường quay lại mục lục và gợi ý đọc tiếp. [Archive lịch sử](history/README.md) giữ tài liệu cũ để tra cứu; không dùng các snapshot trong archive để compile.

## Trạng thái và bằng chứng

Bản hiện tại có 41 RTL/LUT assets, [bảy nhóm PASS](../tests/full_rtl/evidence/opt_final4_all/results.json),
graph **1.066.965 compute clocks**, và [full-top post-fit PASS 100,78 MHz](verification/timing/opt_fulltop7/manifest.json)
ở mọi corner; mọi slack không âm, TNS = 0, không có path unconstrained.
[Host cancellation](../tests/full_rtl/evidence/opt_host1/results.json) và
[portable elaboration](verification/portable_elaboration_opt_final4/results.json) cũng PASS.
Xem [trạng thái hiện tại](verification/optimization_status.md),
[review](reviews/rtl_change_review_v3.md) và [checkpoint workspace](../TASK_STATE.md).
Chưa chạy pretrained application; các kết quả Quartus không phải ASIC signoff.

Top hiện tại là **`llm_soc`**, chạy toàn graph sinh token trên RTL. Compute/control dùng SystemVerilog portable; nhân/chia được viết bằng tích bit, cộng/trừ và dịch. Không có nhánh `SYNTHESIS`/`QUARTUS_SYNTHESIS`, task synthesizable hoặc IP tính toán/control Quartus. Chỉ `quartus_word_ram` chứa `altsyncram`, sau [adapter SRAM có hợp đồng rõ ràng](design/asic_memory_binding.md).

**Quartus chỉ là backend demo EDA.** Thiết kế ưu tiên chuyển sang ASIC bằng cách thay technology leaf SRAM và cung cấp library/constraints phù hợp. Pin, I/O delay và placement trong QSF thuộc backend này; không có mục tiêu bring-up board FPGA. Kết quả Quartus không phải ASIC signoff.

Các checkpoint trong bảng dưới đây là lịch sử trước tối ưu `opt_final4`;
chúng áp dụng cho source/config được lưu trong từng archive.

| Phạm vi xác minh lịch sử | Kết quả và evidence |
|---|---|
| Source lịch sử `cache1`, 34 assets | Tách KV payload FF liên tục khỏi operand binary giữ; [A&S PASS, 0 errors/12 warnings](verification/synthesis/cache1/manifest.json). Reset/latency/state và phép toán giữ nguyên. |
| Coding policy source cache1 | [Inventory và rà soát theo hash](verification/rtl_policy_cache1/results.json): không có runtime nhân/chia, task synthesizable hoặc IP compute/control. Đây là source review, không phải timing/functional proof. |
| Unit source cache1 | [7 nhóm PASS](../tests/full_rtl/evidence/cache1_all_units/results.json), compile/runtime 0 warnings; graph 4.229.462 clock, ba token RTL chọn, 16 lượt layer, causal checks đạt. |
| Portable full-top source cache1 | [Elaboration PASS](verification/portable_elaboration_cache1/results.json), không binding vendor, 24 module units/14 tên, 0 errors/0 warnings. `run 0`, không weights/inference; chưa phải ASIC synthesis/signoff. |
| Timing source cache1/cache2 | [Cache1 fit PASS/timing FAIL 73,97 MHz](verification/timing/fullrtl100_cache1/manifest.json), setup/recovery lỗi ở hai slow corners; hold/removal/pulse đạt, UCP zero. Backend cache2 bỏ ép global theo recommendation, [A&S PASS0errors12warnings](verification/synthesis/cache2/manifest.json); [kết quả cache2](verification/timing/fullrtl100_cache2/manifest.json). [Attention1 trước đó FAIL 92,19 MHz](verification/timing/fullrtl100_attention1/manifest.json); [critical paths lịch sử](verification/timing/README.md). |
| Source trước thay đổi clear attention | [7 nhóm PASS](../tests/full_rtl/evidence/pipeline3_all_units/results.json); [full-top fanout2 timing FAIL 96,67 MHz](verification/timing/fullrtl100_fanout2/manifest.json), setup/hold còn lỗi. Recovery/removal/pulse đạt mọi corner; không có unconstrained paths. |
| Pretrained application toàn graph | Chưa chạy theo gate hiện hành. Chỉ chạy sau khi đúng source/config đạt cả 7 nhóm và post-fit ≥100 MHz, mọi corner/slack/TNS/UCP đạt. Numeric matching và chất lượng đoạn văn được đánh giá riêng. |

Các kết quả cũ, warnings, critical paths, commands và source/config hashes giữ trong [timing hub](verification/timing/README.md), [verification](verification/README.md) và [lịch sử](history/README.md). Core instruction-driven cùng 10 nhóm regression là phạm vi legacy riêng. [Demo NanoFable trước đây](demos/language.md) dùng CPU và replay 168 linear trên RTL; đó chưa phải application toàn graph RTL.

Code trích dẫn, dòng và SHA-256 trong source guide được đối chiếu bởi [validator](source_guide/validate.py); [validation.json](source_guide/validation.json) ghi kết quả. Sau khi sửa RTL, cập nhật chú giải rồi chạy:

```powershell
python docs/source_guide/validate.py
./tests/run.ps1 -Block All
```

Runner, reference, testbench và manifest demo nhẹ được đưa lên repository để chạy lại. Model/checkpoint tải từ nguồn upstream đã pin; dependency, build cache và log được tạo local. Xem [hướng dẫn test](../tests/README.md) và [hướng dẫn demo](demos/README.md).
