# Tài liệu RTL chính

> **Category: GUIDE (tài liệu chính).** Đây là bộ tài liệu chuẩn cho từng module RTL trong `Verilog Source code/`.
> Nó thay cho bộ chú giải snapshot cũ `docs/source_guide/blocks/*.sv.md` (đã gỡ). RTL vẫn là nguồn chuẩn cuối cùng.

[Project](../../README.md) → [Source](../README.md) → **Tài liệu RTL**

## Thứ tự đọc

| Tài liệu | Nội dung |
|---|---|
| [00_kien_thuc_nen.md](00_kien_thuc_nen.md) | Kiến thức nền: clock, FSM, SRAM, fixed-point, transformer |
| [01_tong_quan_kien_truc.md](01_tong_quan_kien_truc.md) | Bức tranh tổng thể, cây module, lộ trình đọc |
| [02_hoat_dong_chi_tiet_llm_soc.md](02_hoat_dong_chi_tiet_llm_soc.md) | `llm_soc` chạy một token từng bước |
| [03_npu_legacy_matmulfree.md](03_npu_legacy_matmulfree.md) | NPU legacy `matmulfree` chạy theo lệnh |
| [modules/](#danh-mục-file-rtl) | 42 tài liệu, mỗi module một file |
| [diagrams/npu_architecture.drawio](diagrams/npu_architecture.drawio) | Sơ đồ draw.io nhiều trang |

Tài liệu tiếng Anh ở `docs/` giữ các phần mà bộ này không sở hữu:
[kiến trúc và numeric contract](../../docs/design/full_rtl_language.md),
[host interface](../../docs/design/host_interface.md),
[full graph và ownership](../../docs/source_guide/full_graph.md),
[trạng thái verification/timing](../../docs/verification/optimization_status.md).

## Danh mục file RTL

Mỗi file trong `Verilog Source code/` có ít nhất một tài liệu. Một số file chứa nhiều module
hoặc tên module khác tên file; cột "Tài liệu" ghi rõ.

| File | Phạm vi | Vai trò | Tài liệu |
|---|---|---|---|
| `llm_soc.sv` | Full graph | Top: host, graph, operator control và sampling | [llm_soc](modules/llm_soc.md) |
| `llm_pkg.sv` | Full graph | Hằng số, layout và helper của graph | [llm_pkg](modules/llm_pkg.md) |
| `reset_release.sv` | Full graph | Reset assert bất đồng bộ, release đồng bộ | [reset_release](modules/reset_release.md) |
| `llm_linear_engine.sv` | Full graph | Stream hàng ternary, credit đọc tham số | [llm_linear_engine](modules/llm_linear_engine.md) |
| `llm_head_engine.sv` | Full graph | Stream 4096 hàng LM head, hai khe scale | [llm_head_engine](modules/llm_head_engine.md) |
| `llm_attention_engine.sv` | Full graph | Score Q·K theo giới hạn causal và maximum | [llm_attention_engine](modules/llm_attention_engine.md) |
| `llm_attention_normalize.sv` | Full graph | Chia chính xác, RNE, dấu và kẹp | [llm_attention_normalize](modules/llm_attention_normalize.md) |
| `llm_math.sv` | Full graph | 32 làn S24 × S32, cây cộng pipeline | [llm_math](modules/llm_math.md) |
| `ternary_dot32.sv` | Full graph | 32 term ternary và reduction có thanh ghi | [ternary_dot32](modules/ternary_dot32.md) |
| `llm_parameter_ram.sv` | Full graph | SRAM tham số 256 bit và host commit | [llm_parameter_ram](modules/llm_parameter_ram.md) |
| `llm_bank_ram.sv` | Full graph | KV/vector bank với lane mask | [llm_bank_ram](modules/llm_bank_ram.md) |
| `llm_exp_lut.svh` | Full graph | Bảng e⁻ˣ 257 mẫu cho softmax (module `llm_exp_sample`) | [llm_exp_sample](modules/llm_exp_sample.md) |
| `llm_gumbel_lut.svh` | Full graph | Bảng Gumbel 256 mẫu cho sampling (module `llm_gumbel_sample`) | [llm_gumbel_sample](modules/llm_gumbel_sample.md) |
| `div.sv` | Dùng chung | Bộ chia unsigned dịch/trừ | [div](modules/div.md) |
| `isqrt_u64.sv` | Dùng chung | Căn bậc hai nguyên U64 | [isqrt_u64](modules/isqrt_u64.md) |
| `logic_mul.sv` | Dùng chung | Nhân bằng bit-product và compressor tree | [logic_mul](modules/logic_mul.md) |
| `npu_pkg.sv` | Dùng chung | Kiểu, saturation và helper RNE | [npu_pkg](modules/npu_pkg.md) |
| `sigmoid.sv` | Dùng chung | Sigmoid: ROM và nội suy | [sigmoid](modules/sigmoid.md) |
| `sigmoid_lut.svh` | Dùng chung | ROM σ(x) 257 mẫu (module `sigmoid_sample`) | [sigmoid_sample](modules/sigmoid_sample.md) |
| `sigmoid_257.mem` | Asset | Bản hex đối chiếu của ROM sigmoid, RTL không nạp | [sigmoid_sample](modules/sigmoid_sample.md) |
| `pipelined_word_ram.sv` | Dùng chung | Adapter SRAM, pipeline request/response | [pipelined_word_ram](modules/pipelined_word_ram.md) |
| `quartus_word_ram.sv` | Dùng chung | Lá công nghệ Quartus duy nhất (`altsyncram`) | [quartus_word_ram](modules/quartus_word_ram.md) |
| `sram_word_tile.sv` | Dùng chung | Lá SRAM portable (mô hình hành vi) | [sram_word_tile](modules/sram_word_tile.md) |
| `matmulfree.sv` | Legacy | Top instruction-driven | [matmulfree](modules/matmulfree.md) |
| `matmul_wrap.sv` | Legacy | Wrapper board: clock/reset/LED | [matmul_wrap](modules/matmul_wrap.md) |
| `PC.sv` | Legacy | Program counter | [PC](modules/PC.md) |
| `ins_mem.sv` | Legacy | Bộ nhớ lệnh 512 × 13 bit | [ins_mem](modules/ins_mem.md) |
| `descriptor_file.sv` | Legacy | Descriptor tensor/ma trận | [descriptor_file](modules/descriptor_file.md) |
| `norm.sv` | Legacy | RMSNorm/QUANT | [norm](modules/norm.md) |
| `norm_dispatch.sv` | Legacy | Kiểm tra descriptor cho NORM | [norm_dispatch](modules/norm_dispatch.md) |
| `ternary_mul.sv` | Legacy | Lõi TMATMUL | [ternary_mul](modules/ternary_mul.md) |
| `acc_mul.sv` | Legacy | Cộng các term ternary | [acc_mul](modules/acc_mul.md) |
| `postscale.sv` | Legacy | Scale/bias sau accumulator (`postscale`, `postscale_finish`) | [postscale](modules/postscale.md) · [postscale_finish](modules/postscale_finish.md) |
| `scale_compose.sv` | Legacy | Ghép scale động | [scale_compose](modules/scale_compose.md) |
| `rowwise_dispatch.sv` | Legacy | Điều phối phép vector | [rowwise_dispatch](modules/rowwise_dispatch.md) |
| `rowwise_op.sv` | Legacy | Datapath phép vector | [rowwise_op](modules/rowwise_op.md) |
| `regfile.sv` | Legacy | SRAM workspace (module `register`) | [register](modules/register.md) |
| `mem_mapping.sv` | Legacy | Wrapper bộ nhớ tham số | [mem_mapping](modules/mem_mapping.md) |
| `sram_256_wrapper.sv` | Legacy | Wrapper SRAM 256 bit | [sram_256_wrapper](modules/sram_256_wrapper.md) |
| `banked_word_ram.sv` | Legacy | Chia tile/mux cho SRAM | [banked_word_ram](modules/banked_word_ram.md) |
| `mul.sv` | Helper | Phép nhân/cộng S16 tham chiếu (`mul`, `addsub`), không thuộc `llm_soc` | [mul](modules/mul.md) · [addsub](modules/addsub.md) |

## Trạng thái hiện tại

Bảng này chỉ tóm tắt; số liệu và bằng chứng thuộc
[optimization_status.md](../../docs/verification/optimization_status.md).

| Mục | Kết quả trên RTL hiện tại (Phase 1B, stream LM head) |
|---|---|
| Mô phỏng | Bảy nhóm, `tb_llm_linear_stream`, `tb_llm_head_stream` PASS trên Xcelium 23.03 và Questa 2024.1 ([evidence](../../tests/full_rtl/evidence/phase1b_20261025/results.json)) |
| Một lượt head | 16.948 chu kỳ (trước: 121.886 ở T = 166, 113.694 ở T = 0) |
| Graph tổng hợp | 280.599 clock (trước: 570.837), 196.619 lệnh host |
| Ứng dụng pretrained | Chạy trực tiếp trên server, ngoài gated flow: 96/96 token khớp, 9.884.334 clock, `overflow = 0` |
| Timing Quartus | 100 MHz đạt ở cả bốn corner, Fmax nhỏ nhất 101,53 MHz; 59.900 ALM, 1.187 RAM block, 0 DSP ([manifest](../../docs/verification/timing/phase1b_head_stream_20261025/manifest.json)) |
| Chưa chạy | Gated `run_application.ps1` và portable elaboration cho RTL này |

Timing Quartus là bằng chứng FPGA, không phải ASIC signoff.

## Quy tắc cập nhật

- Khi RTL tổng hợp được thay đổi, cập nhật `modules/<module>.md` của module đó trong cùng thay đổi.
  File có nhiều module thì cập nhật đúng tài liệu của module bị sửa.
- Thêm module mới thì thêm một tài liệu trong `modules/` và một hàng trong bảng trên.
- Giữ cấu trúc mỗi tài liệu: bảng thông tin, §0 kiến thức nền, §1 tổng quan, §2 cổng,
  §3 sơ đồ khối, §4 hoạt động chi tiết.
- Không chép đoạn RTL dài; chỉ ghi contract, độ trễ, reset và lý do thiết kế.
