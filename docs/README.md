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

RTL dùng **cùng implementation trong mô phỏng và synthesis**, không chọn nhánh theo `SYNTHESIS`/`QUARTUS_SYNTHESIS`. Core có 32 PE ternary, K≤512, accumulator S18, state S16 và SRAM logic 32+8 KiB. Quartus dùng để demo Analysis & Synthesis và timing FPGA; binding SRAM, STA và PPA ASIC cần được đánh giá riêng.

Bản rà soát ngày **01/10/2026** pass **10 mục regression**, compile **0 error/0 warning**. A&S sau tối ưu timing pass **0 error/0 warning**, 7.390 FF và 11.906 ALUT; [timing hub](verification/timing/README.md) ghi baseline và phép đo post-fit riêng. [Báo cáo design](reviews/design_review.md) ghi số liệu, thời điểm, test coverage và các giới hạn.

[Demo NanoFable](demos/language.md) bổ sung sinh văn bản trên CPU và 168 lượt replay linear ternary thực trên RTL; toàn model chưa chạy trên NPU.

Top mới `llm_soc` triển khai toàn graph và SRAM trên RTL. A&S của snapshot
`fullrtl100_tiled` đã fitting thành công nhưng timing FAIL 70,41 MHz.
`fullrtl100_pipeline2` đạt83,58MHz; `local1` đạt84,49MHz. `fullrtl100_tree2`
A&S PASS0/6, fitting PASS0/29, timing vẫn FAIL91,28MHz; sáu nhóm unit đã PASS
đúng source snapshot đó. Current select RTL dùng96one-hot states, SRAM pipeline
và hai tầng chọn lane sigmoid; native graph PASS16layer executions/3tokenRTL,
sáu nhóm unit đã PASS cho snapshot `fullrtl100_select3`, nhưng timing FAIL92,22MHz.
Bản `fullrtl100_group2` có năm nhóm units PASS, fitting PASS0/3 nhưng timing
FAIL81,53MHz gồm setup/hold; full graph ModelSim còn chạy. Xem timing hub/checkpoint
cho source/config hashes, warnings và kết quả mọi corner.
Application pretrained tiếp tục bị chặn đến khi source/config hiện tại đạt đủ gate.

Code trích dẫn, dòng và SHA-256 trong source guide được đối chiếu bởi [validator](source_guide/validate.py); [validation.json](source_guide/validation.json) ghi kết quả. Sau khi sửa RTL, cập nhật chú giải rồi chạy:

```powershell
python docs/source_guide/validate.py
./tests/run.ps1 -Block All
```

Runner, reference, testbench và manifest demo nhẹ được đưa lên repository để chạy lại. Model/checkpoint tải từ nguồn upstream đã pin; dependency, build cache và log được tạo local. Xem [hướng dẫn test](../tests/README.md) và [hướng dẫn demo](demos/README.md).
