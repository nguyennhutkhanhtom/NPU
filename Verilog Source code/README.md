# Source RTL

[Project](../README.md) → [Tài liệu](../docs/README.md) → **Source**

## Chọn top

| Top | Phạm vi | Tài liệu |
|---|---|---|
| llm_soc.sv | Graph LLM cố định: host, prefill, transformer, head và decode | [Kiến trúc hiện tại](../docs/design/full_rtl_language.md) |
| matmulfree.sv | Core instruction-driven legacy: NORM, TMATMUL và vector ops | [Kiến trúc legacy](../docs/design/architecture.md) |
| matmul_wrap.sv | Wrapper legacy khi chọn board top | [Chú giải snapshot](../docs/source_guide/blocks/matmul_wrap.sv.md) |

## Nhóm file

| Nhóm | File chính |
|---|---|
| Graph/control | llm_soc, llm_pkg, reset_release |
| Streaming engines | llm_linear_engine, llm_head_engine, llm_attention_engine, llm_attention_normalize |
| Arithmetic dùng chung | llm_math, ternary_dot32, logic_mul, div, isqrt_u64, sigmoid |
| Memory full graph | llm_parameter_ram, llm_bank_ram, pipelined_word_ram, quartus_word_ram, sram_word_tile |
| Tables | llm_exp_lut, llm_gumbel_lut, sigmoid_lut; sigmoid_257.mem là asset đối chiếu |
| Core legacy | matmulfree, instruction/descriptor, norm, ternary_mul, rowwise và memory wrappers |

[Source overview](../docs/source_guide/full_graph.md) giải thích trách nhiệm,
handshake và pipeline. [Danh mục 41 assets](../docs/source_guide/blocks/README.md)
liên kết từng file, kèm trạng thái của code-excerpt snapshot.

## Build và ranh giới công nghệ

Compute/control dùng SystemVerilog portable; phép nhân/chia được dựng từ logic,
cộng/trừ và shifts. Chỉ quartus_word_ram instantiate altsyncram. ASIC thay
technology leaf theo [SRAM contract](../docs/design/asic_memory_binding.md).

Compile packages trước modules. Full-top Quartus file list nằm trong
[llm_soc.qsf](../quartus/llm_soc.qsf); simulation runner tạo sources.f riêng.
Giữ modules legacy còn được instantiate/kiểm thử và dùng source thư mục này,
không compile một snapshot archive để thay current RTL.

[Host interface](../docs/design/host_interface.md) ·
[Verification](../docs/verification/README.md) ·
[Demo NanoFable](../docs/demos/language.md)
