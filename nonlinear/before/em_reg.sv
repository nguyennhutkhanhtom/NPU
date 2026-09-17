module em_reg(
    input logic clk, rst_n, enable,
    input logic [12:0] instr_em,
    input logic [511:0] alu_out_em,
    input logic [511:0] reg_out_0_em,
    input logic reg_wr_en_em, mem_wr_en_em, mem_rd_en_em_0, mem_rd_en_em_1,
    input logic wb_sel_em,
    input logic [8:0] pc_em,

    output logic [12:0] instr_mw,
    output logic [511:0] alu_out_mw,
    output logic [511:0] reg_out_0_mw,
    output logic reg_wr_en_mw, mem_wr_en_mw, mem_rd_en_mw_0, mem_rd_en_mw_1,
    output logic wb_sel_mw,
    output logic [8:0] pc_mw
);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            instr_mw <= 13'b0;
            alu_out_mw <= '0;
            reg_out_0_mw <= '0;
            reg_wr_en_mw <= 1'b0;
            mem_wr_en_mw <= 1'b0;
            mem_rd_en_mw_0 <= 1'b0;
            mem_rd_en_mw_1 <= 1'b0;
            instr_mw <= 13'b0;
            wb_sel_mw <= 1'b0;
            pc_mw <= 9'b0;
        end
        else if (enable) begin
            instr_mw <= instr_em;
            alu_out_mw <= alu_out_em;
            reg_out_0_mw <= reg_out_0_em;
            reg_wr_en_mw <= reg_wr_en_em;
            mem_wr_en_mw <= mem_wr_en_em;
            mem_rd_en_mw_0 <= mem_rd_en_em_0;
            mem_rd_en_mw_1 <= mem_rd_en_em_1;
            instr_mw <= instr_em;
            wb_sel_mw <= wb_sel_em;
            pc_mw <= pc_em;
        end
    end

endmodule