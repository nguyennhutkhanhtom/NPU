# NPU ternary và graph ngôn ngữ trên RTL

Top hiện tại [`llm_soc`](docs/design/full_rtl_language.md) tự chạy toàn graph
NanoFable: embedding, affine RMSNorm, Q/K/V/O, RoPE, KV cache, causal attention,
softmax, SwiGLU, residual, final norm, language head, token selection và vòng
autoregressive. Host chỉ nạp dữ liệu/config/prompt và tokenizer/decode.
SRAM gồm 768 KiB parameter, 384 KiB KV và 9 KiB vectors.

Compute/control là RTL portable: FF, mux, comparator, bitwise, cộng/trừ và dịch.
Nhân dùng [`logic_mul`](docs/source_guide/blocks/logic_mul.sv.md), chia/sqrt dùng
dịch/trừ; không có runtime toán tử nhân/chia hoặc IP compute/control Quartus.
Chỉ SRAM technology leaf chứa `altsyncram`, sau [adapter thay bằng SRAM ASIC](docs/design/asic_memory_binding.md).
Quartus là backend demo EDA; không có mục tiêu bring-up board FPGA hoặc ASIC signoff.

Source `cache1` đã [A&S PASS, 0 errors/12 warnings](docs/verification/synthesis/cache1/manifest.json),
[cả 7 nhóm test PASS, 0 warnings](tests/full_rtl/evidence/cache1_all_units/results.json)
và [vendor-free elaboration PASS](docs/verification/portable_elaboration_cache1/results.json).
Graph synthetic chạy 4.229.462 clock, chọn ba token bằng RTL và đạt causal checks.
Fitting đã PASS; [timing `fullrtl100_cache1`](docs/verification/timing/fullrtl100_cache1/manifest.json) FAIL 73,97 MHz/setup+recovery.
Chưa có bằng chứng full top đạt 100 MHz.
[Timing trước đó](docs/verification/timing/fullrtl100_attention1/manifest.json) FAIL 92,19 MHz.
Application pretrained chờ exact-current timing mọi corner/slack/TNS/UCP đạt.
Numeric/token matching và chất lượng đoạn văn được đánh giá riêng.

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

Preceding attention1 source clears accumulators at each head entry; [all seven groups](tests/full_rtl/evidence/attention1_all_units/results.json) PASS0compile/runtimewarnings, graph4229462compute clocks/three RTL-selected tokens/16layer executions. Full-top attention1 timing FAIL92.19MHz/setup+recovery; hold PASS every corner. No trained application gate is open.
