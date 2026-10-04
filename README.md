# NPU ternary và graph ngôn ngữ trên RTL

Top hiện tại [`llm_soc`](docs/design/full_rtl_language.md) tự chạy toàn graph
NanoFable: 4 transformer layers, affine RMSNorm, attention/KV, SwiGLU, tied
head, selection và vòng autoregressive. Host chỉ nạp dữ liệu/config/prompt.
SRAM gồm 768 KiB parameter, 384 KiB KV và 9 KiB vectors; area là ưu tiên sau
correctness và timing. [Timing full top](docs/verification/timing/README.md)
ghi đầy đủ lịch sử, constraints và critical paths. Parameter/KV/vector dùng
IP RAM M10K qua adapter thay được bằng SRAM ASIC; đây là vendor IP duy nhất.
Bản trước fix clear attention có cả bảy nhóm regression PASS, gồm kiểm thử RAM thật và graph
tự sinh token từ fixture. Fitting hoàn tất, timing fanout2 FAIL96,67MHz; chưa có bằng chứng full top
đạt100MHz. Application pretrained chờ timing mọi corner đạt cho đúng source.

Revision hiện tại thay toàn bộ phép nhân datapath full/legacy bằng
[`logic_mul`](docs/source_guide/blocks/logic_mul.sv.md): AND/XOR/OR, dịch và cộng,
không dùng toán tử nhân/chia hoặc arithmetic IP. Divider/sqrt dùng dịch/trừ.
[ASIC portability](docs/design/asic_portability.md) quy định boundary SRAM và
standard cells. Full-top A&S bằng Quartus Lite25.1std PASS0errors/12warnings;
`fullrtl100_logic5` fit PASS0DSP/PLL/DLL/HSSI nhưng timing FAIL99,07MHz:
setup/hold/removal còn vi phạm. Logic6 cũng FAIL99,07MHz;logic7 FAIL96,04MHz. [Bảy nhóm unit](tests/full_rtl/evidence/logic6q5_all_units/results.json)
đã PASS cho snapshot35source cũ,0warnings. Bản 33assets đã chuyển
task/pipeline/LUT sang [RTL tường minh](docs/design/rtl_style.md); [cả 7 nhóm regression PASS](tests/full_rtl/evidence/explicit3_all_units/results.json), timing mới FAIL93,28MHz/setup/removal,
Bản trước fix clear attention34assets bỏ SIMD payload enable dư thừa và dùng hai FF reset release; cả bảy nhóm regression PASS. Timing fanout2 FAIL96,67MHz/setup+hold; recovery/removal đạt mọi corner. Chưa có100MHz PASS hoặc pretrained application.

Core instruction-driven `matmulfree` và các kết quả dưới đây được giữ làm
tài liệu của kiến trúc trước. Timing hoặc demo hybrid của core này không
thay thế bằng chứng toàn graph.

RTL SystemVerilog cho inference số nguyên: **32 PE ternary**, activation S8, accumulator S18, state S16, K≤512 và SRAM 256 bit với dung lượng logic **32 KiB parameter + 8 KiB workspace**. Host nạp weight, descriptor và instruction; core chạy NORM + QUANT, TMATMUL và các phép vector.

**[Mở mục lục tài liệu](docs/README.md)**

| Cần xem | Trang chính |
|---|---|
| Thiết kế và bảng bit | [Kiến trúc](docs/design/architecture.md) |
| Lập trình core | [ISA, descriptor và host map](docs/design/interfaces.md) |
| Sơ đồ và code từng khối | [RTL guide](docs/source_guide/README.md) · [Mục lục module](docs/source_guide/blocks/README.md) |
| Chạy test, synthesis và timing | [Verification](docs/verification/README.md) · [Critical path và Fmax](docs/verification/timing/README.md) |
| Model demo | [MNIST và ngôn ngữ](docs/demos/README.md) |
| Các thay đổi và tài liệu gốc | [Design review](docs/reviews/design_review.md) · [Lịch sử](docs/history/README.md) |

## Kết quả core trước

Bản ngày **01/10/2026** pass **10 mục regression** và demo Quartus Analysis & Synthesis với **0 error/0 warning**. Checkpoint **Binary-MNIST160** đúng nhãn trên **10/10 ảnh mẫu**, 40 lượt tầng khớp bit-exact với reference số nguyên; xem [phạm vi và kết quả demo](docs/demos/mnist.md).

[NanoFable-1M-ternary](docs/demos/language.md): CPU chạy **3 prompt × 32 token greedy**, lặp lại cho cùng kết quả. RTL pass **168 lượt linear ternary thực**, đối chiếu **33.792 output S32**. Sinh văn bản toàn graph chạy trên CPU; NPU kiểm chứng các linear được stream từng tầng, chưa chạy toàn model.

RTL compute dùng một implementation cho mô phỏng và synthesis, không phụ thuộc nhánh macro hay primitive Quartus; adapter bộ nhớ FPGA chứa altsyncram. Mục tiêu là ASIC; A&S và timing FPGA là các bước demo tổng hợp và critical path; xem [constraint/Fmax](docs/verification/timing/README.md). Chưa có xác nhận binding SRAM PDK, STA hoặc PPA ASIC.

## Chạy lại

```powershell
./tests/run.ps1 -Block All
./tests/full_rtl/run_units.ps1
# Full application requires an exact-current-source passing timing manifest:
./tests/full_rtl/run_application.ps1 -TimingManifest docs/verification/timing/PASS_TAG/manifest.json
```

Xem [cài đặt và chọn test](tests/README.md), [demo checkpoint](tests/model_demo/README.md) và [mục lục demo](docs/demos/README.md) để chuẩn bị tool/dependency. Các script và manifest nhẹ được quản lý trong repository; runtime, checkpoint tải về và build cache được tạo local.

## Thư mục

| Thư mục | Nội dung |
|---|---|
| [Verilog Source code](<Verilog Source code/README.md>) | Source RTL hiện hành và LUT hằng |
| [docs](docs/README.md) | Tài liệu thiết kế, RTL guide, verification, demo và lịch sử |
| [tests](tests/README.md) | Regression/reference, runners và demo export |
| `quartus` | Project demo A&S; không quyết định kiến trúc ASIC |

Current attention1 source clears accumulators at each head entry; [all seven groups](tests/full_rtl/evidence/attention1_all_units/results.json) PASS0compile/runtimewarnings, graph4229462compute clocks/three RTL-selected tokens/16layer executions. Full-top attention1 timing FAIL92.19MHz/setup+recovery; hold PASS every corner. No trained application gate is open.
