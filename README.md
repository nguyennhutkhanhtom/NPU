# NPU ternary và graph ngôn ngữ trên RTL

Top hiện tại [`llm_soc`](docs/design/full_rtl_language.md) tự chạy toàn graph
NanoFable: 4 transformer layers, affine RMSNorm, attention/KV, SwiGLU, tied
head, selection và vòng autoregressive. Host chỉ nạp dữ liệu/config/prompt.
SRAM gồm 768 KiB parameter, 384 KiB KV và 9 KiB vectors; area là ưu tiên sau
correctness và timing. [Timing full top](docs/verification/timing/README.md)
đã cải thiện70,41→83,58→84,49→91,28→92,22MHz, vẫn FAIL. Snapshot
`fullrtl100_select3` có sáu nhóm units PASS. Bản giảm fanout scalar và chốt
host output trước có năm nhóm units PASS; tag `fullrtl100_group2` fitting PASS
nhưng timing FAIL81,53MHz, gồm setup và hold. Hiện parameter/KV/vector dùng
IP RAM M10K qua adapter thay được bằng SRAM ASIC. Không dùng DSP/PLL hay
compute IP khác. Kiểm thử IP thực tế PASS158checks; regression bảy nhóm
đang xác minh revision pipeline mới. Milestone `d3825b2` đã push;
`fullrtl100_memoryip2` synthesis/fit PASS,
0DSP/0PLL, nhưng timing FAIL87,49MHz. Bản byte-product tiếp theo
`fullrtl100_bytes1` đạt89,60MHz, vẫn FAIL setup/hold. `fullrtl100_control1`
có sáu nhóm units PASS, fit0DSP/PLL/DLL/HSSI, nhưng timing FAIL92,75MHz gồm
setup/hold/recovery. Pipeline chọn ternary, exp delta, clamp và enable KV cục bộ
đã được kiểm chứng bằng units; full graph còn pending. Clock LVDS thông thường
đi trực tiếp tới GCLK, không PLL/SERDES, chưa giải quyết clock/pad/reset timing.
Application pretrained chờ đủ gate source/config hiện tại và unit tests.

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
