new_project lint_cand -force
read_file -type verilog {rtl/npu_pkg.sv rtl/llm_pkg.sv rtl/acc_mul.sv rtl/banked_word_ram.sv rtl/descriptor_file.sv rtl/div.sv rtl/ins_mem.sv rtl/isqrt_u64.sv rtl/llm_attention_engine.sv rtl/llm_attention_normalize.sv rtl/llm_bank_ram.sv rtl/llm_head_engine.sv rtl/llm_linear_engine.sv rtl/llm_math.sv rtl/llm_parameter_ram.sv rtl/llm_soc.sv rtl/logic_mul.sv rtl/matmulfree.sv rtl/matmul_wrap.sv rtl/mem_mapping.sv rtl/mul.sv rtl/norm_dispatch.sv rtl/norm.sv rtl/PC.sv rtl/pipelined_word_ram.sv rtl/postscale.sv rtl/quartus_word_ram.sv rtl/regfile.sv rtl/reset_release.sv rtl/rowwise_dispatch.sv rtl/rowwise_op.sv rtl/scale_compose.sv rtl/sigmoid.sv rtl/sram_256_wrapper.sv rtl/sram_word_tile.sv rtl/ternary_dot32.sv rtl/ternary_mul.sv}
set_option enableSV12 yes
set_option incdir {rtl}
set_option top llm_soc
set_option mthresh 65536
set_option param {llm_soc.USE_QUARTUS_MEMORY=0}
current_methodology $env(SPYGLASS_HOME)/GuideWare/latest/block/rtl_handoff
current_goal lint/lint_rtl -top llm_soc
run_goal
write_report moresimple > moresimple.rpt
write_report summary > summary.rpt
save_project
exit -force
