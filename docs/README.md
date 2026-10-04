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
| Chuyển sang ASIC và kiểm tra policy IP | [ASIC portability](design/asic_portability.md) | [Cây nhân bit](source_guide/blocks/logic_mul.sv.md), [SRAM binding](source_guide/blocks/quartus_word_ram.sv.md) |
| Thay SRAM technology leaf và kiểm tra bộ nhớ nhỏ | [ASIC memory binding](design/asic_memory_binding.md) | [Elaboration không nạp vendor RAM](verification/portable_elaboration1/results.json) |
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

Top hiện tại là **`llm_soc`**, chạy toàn graph sinh token trên RTL. Compute/control dùng SystemVerilog portable; nhân/chia được viết bằng tích bit, cộng/trừ và dịch. Không có nhánh `SYNTHESIS`/`QUARTUS_SYNTHESIS`, task synthesizable hoặc IP tính toán/control Quartus. Chỉ `quartus_word_ram` chứa `altsyncram`, sau [adapter SRAM có hợp đồng rõ ràng](design/asic_memory_binding.md).

**Quartus chỉ là backend demo EDA.** Thiết kế ưu tiên chuyển sang ASIC bằng cách thay technology leaf SRAM và cung cấp library/constraints phù hợp. Pin, I/O delay và placement trong QSF thuộc backend này; không có mục tiêu bring-up board FPGA. Kết quả Quartus không phải ASIC signoff.

| Phạm vi xác minh | Kết quả và evidence |
|---|---|
| Source hiện tại `attention1`, 34 assets | Clear accumulator attention tại đầu mỗi head; [A&S PASS, 0 errors/12 warnings](verification/synthesis/attention1/manifest.json). |
| Coding policy source hiện tại | [Inventory và rà soát theo hash](verification/rtl_policy_attention1/results.json): không có runtime nhân/chia, task synthesizable hoặc IP compute/control. Đây là source review, không phải timing/functional proof. |
| Unit source hiện tại | [6 nhóm PASS](../tests/full_rtl/evidence/attention1_six_units/results.json), compile/runtime 0 warnings; graph đang chạy. Chưa có kết luận cả 7 nhóm PASS. |
| Timing source hiện tại | Fitter đang chạy với SDC 10 ns giữ nguyên; chưa có timing PASS. Theo dõi [checkpoint](../TASK_STATE.md) và [timing hub](verification/timing/README.md). |
| Source trước thay đổi clear attention | [7 nhóm PASS](../tests/full_rtl/evidence/pipeline3_all_units/results.json); [full-top fanout2 timing FAIL 96,67 MHz](verification/timing/fullrtl100_fanout2/manifest.json), setup/hold còn lỗi. Recovery/removal/pulse đạt mọi corner; không có unconstrained paths. |
| Pretrained application toàn graph | Chưa chạy theo gate hiện hành. Chỉ chạy sau khi đúng source/config đạt cả 7 nhóm và post-fit ≥100 MHz, mọi corner/slack/TNS/UCP đạt. Numeric matching và chất lượng đoạn văn được đánh giá riêng. |

Các kết quả cũ, warnings, critical paths, commands và source/config hashes giữ trong [timing hub](verification/timing/README.md), [verification](verification/README.md) và [lịch sử](history/README.md). Core instruction-driven cùng 10 nhóm regression là phạm vi legacy riêng. [Demo NanoFable trước đây](demos/language.md) dùng CPU và replay 168 linear trên RTL; đó chưa phải application toàn graph RTL.

Code trích dẫn, dòng và SHA-256 trong source guide được đối chiếu bởi [validator](source_guide/validate.py); [validation.json](source_guide/validation.json) ghi kết quả. Sau khi sửa RTL, cập nhật chú giải rồi chạy:

```powershell
python docs/source_guide/validate.py
./tests/run.ps1 -Block All
```

Runner, reference, testbench và manifest demo nhẹ được đưa lên repository để chạy lại. Model/checkpoint tải từ nguồn upstream đã pin; dependency, build cache và log được tạo local. Xem [hướng dẫn test](../tests/README.md) và [hướng dẫn demo](demos/README.md).
