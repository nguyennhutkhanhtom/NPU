# NPU ternary cho ASIC inference nhỏ

RTL SystemVerilog cho inference số nguyên: **32 PE ternary**, activation S8, accumulator S18, state S16, K≤512 và SRAM 256 bit với dung lượng logic **32 KiB parameter + 8 KiB workspace**. Host nạp weight, descriptor và instruction; core chạy NORM + QUANT, TMATMUL và các phép vector.

**[Mở mục lục tài liệu](docs/README.md)**

| Cần xem | Trang chính |
|---|---|
| Thiết kế và bảng bit | [Kiến trúc](docs/design/architecture.md) |
| Lập trình core | [ISA, descriptor và host map](docs/design/interfaces.md) |
| Sơ đồ và code từng khối | [RTL guide](docs/source_guide/README.md) · [Mục lục module](docs/source_guide/blocks/README.md) |
| Chạy test và kiểm tra synthesis | [Verification](docs/verification/README.md) |
| Model demo | [MNIST và ngôn ngữ](docs/demos/README.md) |
| Các thay đổi và tài liệu gốc | [Design review](docs/reviews/design_review.md) · [Lịch sử](docs/history/README.md) |

## Trạng thái

Bản ngày **01/10/2026** pass **9 mục regression** và demo Quartus Analysis & Synthesis với **0 error/0 warning**. Checkpoint **Binary-MNIST160** đúng nhãn trên **10/10 ảnh mẫu**, 40 lượt tầng khớp bit-exact với reference số nguyên; xem [phạm vi và kết quả demo](docs/demos/mnist.md).

[NanoFable-1M-ternary](docs/demos/language.md): CPU chạy **3 prompt × 32 token greedy**, lặp lại cho cùng kết quả. RTL pass **168 lượt linear ternary thực**, đối chiếu **33.792 output S32**. Sinh văn bản toàn graph chạy trên CPU; NPU kiểm chứng các linear được stream từng tầng, chưa chạy toàn model.

RTL dùng một implementation cho mô phỏng và synthesis, không phụ thuộc nhánh macro hay primitive Quartus. Mục tiêu là ASIC; A&S FPGA là bước kiểm tra khả năng tổng hợp. Chưa có xác nhận binding SRAM PDK, STA hoặc PPA ASIC.

## Chạy lại

```powershell
./tests/run.ps1 -Block All
./tests/model_demo/run.ps1
./tests/language_demo/run.ps1
```

Xem [cài đặt và chọn test](tests/README.md), [demo checkpoint](tests/model_demo/README.md) và [mục lục demo](docs/demos/README.md) để chuẩn bị tool/dependency. Các script và manifest nhẹ được quản lý trong repository; runtime, checkpoint tải về và build cache được tạo local.

## Thư mục

| Thư mục | Nội dung |
|---|---|
| [Verilog Source code](<Verilog Source code/README.md>) | Source RTL hiện hành và LUT hằng |
| [docs](docs/README.md) | Tài liệu thiết kế, RTL guide, verification, demo và lịch sử |
| [tests](tests/README.md) | Regression/reference, runners và demo export |
| `quartus` | Project demo A&S; không quyết định kiến trúc ASIC |
