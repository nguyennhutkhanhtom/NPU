# Tài liệu NPU ternary

[Trang project](../README.md) → **Tài liệu**

Đây là điểm bắt đầu cho bản RTL hiện hành. Tài liệu được chia theo việc cần làm: hiểu thiết kế, lập trình qua host, đọc code, kiểm chứng, chạy model và tra cứu lịch sử. Source đang phát triển nằm trong [Verilog Source code](<../Verilog Source code/README.md>).

## Đọc theo thứ tự

**[Kiến trúc](design/architecture.md) → [ISA và host](design/interfaces.md) → [Sơ đồ RTL](source_guide/README.md) → [Từng khối](source_guide/blocks/README.md) → [Kiểm chứng](verification/README.md) → [Demo model](demos/README.md)**

| Bạn muốn làm gì? | Bắt đầu ở đây | Đọc tiếp |
|---|---|---|
| Hiểu core 32 PE, format số và SRAM | [Kiến trúc và bảng bit](design/architecture.md) | [Hierarchy và luồng dữ liệu](source_guide/README.md) |
| Hiểu toàn graph sinh token trên RTL | [Autonomous language graph](design/full_rtl_language.md) | [Host, numeric và gate tests](../tests/full_rtl/README.md) |
| Nạp dữ liệu hoặc viết chương trình | [Instruction, descriptor, host map và LUT](design/interfaces.md) | [Cách export và chạy model](demos/README.md) |
| Sửa một module RTL | [Mục lục từng file](source_guide/blocks/README.md) | [Các cải tiến và hợp đồng hiện hành](reviews/design_review.md) |
| Chạy test, xem synthesis hoặc timing | [Regression và demo synthesis](verification/README.md) | [Critical path và Fmax post-fit](verification/timing/README.md) |
| Chạy model có checkpoint | [Danh sách demo](demos/README.md) | [MNIST trên RTL](demos/mnist.md), [ngôn ngữ CPU + linear RTL](demos/language.md) |
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
`fullrtl100_pipeline2` cải thiện lên 83,58 MHz, vẫn timing FAIL. Source hiện tại
đã sửa signed attention, tie selection S32_MIN và reserved ternary code, dùng
FSM one-hot cùng local SRAM request registers; `fullrtl100_local1` A&S PASS
0 error/6 warning, fitting PASS0/4, timing vẫn FAIL84,49MHz. Sáu nhóm unit
đã PASS trên source này, gồm graph16layer executions/3tokenRTL.
Application pretrained tiếp tục bị chặn đến khi source/config hiện tại đạt đủ gate.

Code trích dẫn, dòng và SHA-256 trong source guide được đối chiếu bởi [validator](source_guide/validate.py); [validation.json](source_guide/validation.json) ghi kết quả. Sau khi sửa RTL, cập nhật chú giải rồi chạy:

```powershell
python docs/source_guide/validate.py
./tests/run.ps1 -Block All
```

Runner, reference, testbench và manifest demo nhẹ được đưa lên repository để chạy lại. Model/checkpoint tải từ nguồn upstream đã pin; dependency, build cache và log được tạo local. Xem [hướng dẫn test](../tests/README.md) và [hướng dẫn demo](demos/README.md).
