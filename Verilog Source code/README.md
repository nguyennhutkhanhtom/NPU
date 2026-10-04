# Source RTL NPU

[Project](../README.md) → [Tài liệu](../docs/README.md) → **Source RTL**

Thư mục này là source đang phát triển. Top toàn graph là `llm_soc.sv`; `matmulfree.sv` và `matmul_wrap.sv` thuộc kiến trúc legacy. Compute/control dùng cùng RTL cho mô phỏng và synthesis, không có nhánh `SYNTHESIS`/`QUARTUS_SYNTHESIS`. FPGA dùng `quartus_word_ram.sv` chứa IP `altsyncram` sau adapter `pipelined_word_ram`; đây là boundary để thay SRAM ASIC sau này. Không dùng DSP, PLL hoặc compute IP khác; arithmetic được ánh xạ sang logic cells thường.

| Cần tra cứu | Tài liệu |
|---|---|
| Toàn graph, numeric formats và SRAM contracts | [Full RTL language](../docs/design/full_rtl_language.md) |
| Host/tests/application của top hiện tại | [Full RTL tests](../tests/full_rtl/README.md) |
| Opcode, descriptor, scale động, host map, LUT và build | [Interface hiện hành](../docs/design/interfaces.md) |
| Cấu hình 32 PE, K≤512, format số và SRAM 32+8 KiB | [Kiến trúc](../docs/design/architecture.md) |
| Engine, memory và scheduler nối với nhau thế nào | [Hierarchy và luồng dữ liệu](../docs/source_guide/README.md) |
| Vai trò, sơ đồ và code trích dẫn của mỗi file | [Mục lục giải thích RTL](../docs/source_guide/blocks/README.md) |
| Lỗi đã sửa, cải tiến và giới hạn ASIC | [Design review](../docs/reviews/design_review.md) |
| Regression và demo synthesis | [Verification](../docs/verification/README.md) |

## Nhóm source

- **Toàn graph:** `llm_soc`, `llm_math`, `llm_pkg`, các bảng exp/Gumbel, và `reset_release`; compute/controller không dùng vendor IP.
- **SRAM toàn graph:** `llm_parameter_ram`, `llm_bank_ram`, `pipelined_word_ram`; chỉ leaf `quartus_word_ram` instantiate `altsyncram`. Xem ports/latency/collision/reset trong tài liệu full graph.
- **Số học chung:** `logic_mul` dùng cây tích bit và compressor; divider/sqrt/rounding dùng logic portable.

Những nhóm bên dưới còn được top legacy instantiate và có regression riêng:

- **Control:** `matmulfree`, `PC`, `ins_mem`, `descriptor_file`.
- **NORM/scalar:** `norm_dispatch`, `norm` (gồm `isqrt_u64`), `div`, `scale_compose`.
- **Ternary:** `ternary_mul`, `acc_mul`, `postscale`.
- **Vector:** `rowwise_dispatch`, `rowwise_op`, `sigmoid` và LUT hằng `sigmoid_lut.svh`; `sigmoid_257.mem` giữ cùng mẫu để generate/đối chiếu.
- **Memory:** `sram_256_wrapper`, `regfile`, `mem_mapping`; synchronous read/valid, data array không reset.
- **Kiểu dữ liệu/số học:** `npu_pkg`; compile package trước các module.

Các controller/helper không có caller đã được dọn; [bảng từng file](../docs/source_guide/blocks/README.md) chỉ dẫn source hiện có. Giữ các module legacy còn được instantiate và kiểm thử. Không dùng snapshot trong archive để compile.

Chạy regression legacy từ thư mục gốc bằng `./tests/run.ps1 -Block All`; dùng [full RTL runner](../tests/full_rtl/README.md) cho `llm_soc`. Quartus dùng để demo synthesis/fitting/timing FPGA; chưa xác nhận PPA, SRAM views hoặc signoff ASIC.
