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

Bản hiện tại triển khai [tối ưu bit-exact](docs/design/exact_throughput_optimization.md):
cache operand/scale, packed stores, ternary dot, bounded prefetch, streaming head/QK,
fused probability/V, bốn divider và bốn sigmoid lane. [Cả bảy nhóm đã PASS](tests/full_rtl/evidence/opt_final4_all/results.json)
với 0 compile/runtime warnings; graph chạy **1.066.965 compute clocks**, giảm
**74,92%** so với baseline và giữ nguyên ba token. [Vendor-free elaboration PASS](docs/verification/portable_elaboration_opt_final4/results.json).
[Full-top post-fit timing PASS](docs/verification/timing/opt_fulltop7/manifest.json):
Fmax thấp nhất **100,78 MHz** ở cả bốn corner, worst setup **+0,077 ns**,
mọi slack không âm, TNS = 0, không có path unconstrained; hash RTL/cấu hình khớp.
Tài nguyên fit tăng **10,43% ALM**, **20,66% register**; RAM blocks giữ nguyên,
DSP = 0. Xem
[trạng thái và lệnh tái hiện](docs/verification/optimization_status.md).
Baseline được giữ nguyên trong `docs/verification/optimization_baseline`:
graph 4.254.046 compute clocks, cả bảy nhóm PASS; [timing `npu100_b2`](docs/verification/timing/npu100_b2/manifest.json)
FAIL 98,39 MHz, worst setup -0,164 ns; đây là bằng chứng lịch sử trước tối ưu.
Bản mặc định bốn divider/bốn sigmoid lane đã đạt các điều kiện kiểm chứng phần cứng
exact-current unit/graph và timing; task này chưa chạy application pretrained.
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
| Các thay đổi và tài liệu gốc | [Các báo cáo review](docs/reviews/README.md) · [Lịch sử](docs/history/README.md) |

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
| [quartus](quartus/README.md) | Backend đang dùng; project thử nghiệm cũ trong `quartus/archive/` |
| [tools/optimization](tools/optimization/README.md) | Công cụ lưu checkpoint và tính tỷ lệ thay đổi RTL |

Các báo cáo `rtl_change_review*.md` nằm trong [docs/reviews](docs/reviews/README.md),
tài liệu nghiên cứu nằm tại [docs/design/architecture_research.md](docs/design/architecture_research.md).
Xem [TASK_STATE.md](TASK_STATE.md) để tới evidence và lệnh kiểm chứng hiện tại.
