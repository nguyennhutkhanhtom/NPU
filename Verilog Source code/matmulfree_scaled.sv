// Width-only scaled profile. Known functional bugs are intentionally retained.
// Same 5-stage pipeline, 13-bit ISA, 8 registers, 32 lanes, 512-element vectors.
module matmulfree_scaled #(
    parameter MEM_INIT_FILE="mem_init_8.mem",
    parameter INSTR_INIT_FILE="instruction_64.mem",
    parameter SIG_INIT_FILE="sigContent_8.mif",
    parameter EXP_INIT_FILE="exp_content_8.mif"
) (
    input logic rst_n, clk,
    output logic ready, overflow_out, carry_out,
    output logic [5:0] pc_debug,
    output logic [12:0] instr_debug,
    output logic [255:0] mem_out_1_debug
);
    matmulfree #(
        .DATA_WIDTH(8), .FRAC_WIDTH(4),
        .REG_DEPTH(128), .MEM_DEPTH(16384), .INSTR_DEPTH(64),
        .EXP_LUT_DEPTH(512),
        .MEM_INIT_FILE(MEM_INIT_FILE), .INSTR_INIT_FILE(INSTR_INIT_FILE),
        .SIG_INIT_FILE(SIG_INIT_FILE), .EXP_INIT_FILE(EXP_INIT_FILE)
    ) core (.*);
endmodule
