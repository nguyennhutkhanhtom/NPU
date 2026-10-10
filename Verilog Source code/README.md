# Source RTL

New to RTL? Read [NPU and RTL fundamentals](../docs/00-start-here/fundamentals.md)
before opening individual modules, then use the [module catalog](../docs/source_guide/blocks/README.md)
to find the block that owns the behavior you want to understand.

Current flow: [Xcelium/Genus in Slurm](../tools/server/README.md), packages before modules, remove `quartus_word_ram.sv`, default top `USE_QUARTUS_MEMORY=0`.


> **Category: GUIDE.**

[Project](../README.md) → [Documentation](../docs/README.md) → **Source**

## Choose top

| Top | Scope | Documentation |
|---|---|---|
| llm_soc.sv | Fixed Graph LLM: host, prefill, transformer, head, and decode | [Current architecture](../docs/design/full_rtl_language.md) |
| matmulfree.sv | Core instruction-driven legacy: NORM, TMATMUL, and vector ops | [Legacy architecture](<../docs/design/legacy/architecture.md>) |
| matmul_wrap.sv | Legacy wrapper when selecting top board | [Snapshot commentary](../docs/source_guide/blocks/matmul_wrap.sv.md) |

## File group

| Group | Main file |
|---|---|
| Graph/control | llm_soc, llm_pkg, reset_release |
| Streaming engines | llm_linear_engine, llm_head_engine, llm_attention_engine, llm_attention_normalize |
| Common arithmetic | llm_math, ternary_dot32, logic_mul, div, isqrt_u64, sigmoid |
| Full graph memory | llm_parameter_ram, llm_bank_ram, pipelined_word_ram, quartus_word_ram, sram_word_tile |
| Tables | llm_exp_lut, llm_gumbel_lut, sigmoid_lut; sigmoid_257.mem is the reference asset |
| Legacy core | matmulfree, instruction/descriptor, norm, ternary_mul, rowwise and memory wrappers |

[Source overview](../docs/source_guide/full_graph.md) explains responsibilities,
handshake and pipeline. [List of 41 assets](../docs/source_guide/blocks/README.md)
links each file, along with the status of code-excerpt snapshots.

## Build and technology boundaries

Compute/control uses portable SystemVerilog; multiplication/division is constructed from logic,
addition/subtraction and shifts. Only quartus_word_ram instantiates altsyncram. ASIC replaces
technology leaf according to [SRAM contract](../docs/design/asic_memory_binding.md).

Compile packages before modules. Full-top Quartus file list is in
[llm_soc.qsf](../quartus/llm_soc.qsf); simulation runner generates a separate sources.f.
Keep legacy modules that can still be instantiated/tested and use this source directory,
do not compile a snapshot archive to replace the current RTL.

[Host interface](../docs/design/host_interface.md) ·
[Verification](../docs/verification/README.md) ·
[Demo NanoFable](../docs/demos/language.md)
