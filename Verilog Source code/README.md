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

- **Control:** `matmulfree`, `PC`, `ins_mem`, `descriptor_file`.
- **NORM/scalar:** `norm_dispatch`, `norm` (gồm `isqrt_u64`), `div`, `scale_compose`.
- **Ternary:** `ternary_mul`, `acc_mul`, `postscale`.
- **Vector:** `rowwise_dispatch`, `rowwise_op`, `sigmoid` và LUT hằng `sigmoid_lut.svh`; `sigmoid_257.mem` giữ cùng mẫu để generate/đối chiếu.
- **Memory:** `sram_256_wrapper`, `regfile`, `mem_mapping`; synchronous read/valid, data array không reset.
- **Kiểu dữ liệu/số học:** `npu_pkg`; compile package trước các module.

Các module pipeline/DDR cũ và helper được đánh dấu trạng thái riêng trong [bảng từng file](../docs/source_guide/blocks/README.md); top hiện hành không instantiate chúng. Không dùng snapshot trong archive để compile.

Chạy regression từ thư mục gốc bằng `./tests/run.ps1 -Block All`. [Hướng dẫn test](../tests/README.md) mô tả tool, tùy chọn và kết quả. Quartus chỉ dùng để demo khả năng A&S; bản này chưa xác nhận timing/PPA hoặc binding SRAM ASIC.
