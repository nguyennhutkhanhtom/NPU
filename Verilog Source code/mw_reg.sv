module mw_reg #(parameter WORD_W=512, PC_W=9) (
    input logic clk, rst_n, flush,
    input logic [12:0] instr_mw,
    input logic [WORD_W-1:0] mem_out_mw_0, 
    input logic [WORD_W-1:0] alu_out_mw,
    input logic wb_sel_mw,
    input logic reg_wr_en_mw, 
    input logic enable,
    input logic [PC_W-1:0] pc_mw,

    output logic [12:0] instr_wb,
    output logic [WORD_W-1:0] mem_out_wb_0,
    output logic [WORD_W-1:0] alu_out_wb,
    output logic reg_wr_en_wb,
    output logic wb_sel_wb,
    output logic [PC_W-1:0] pc_wb
);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_out_wb_0 <= '0;
            alu_out_wb <= '0;
            reg_wr_en_wb <= 1'b0;
            instr_wb <= 13'b0;
            wb_sel_wb <= 1'b0;
            pc_wb <= '0;
        end
        else if(flush) begin
            mem_out_wb_0 <= '0;
            alu_out_wb <= '0;
            reg_wr_en_wb <= 1'b0;
            instr_wb <= 13'b0;
            wb_sel_wb <= 1'b0;
            pc_wb <= '0;
        end
        else if (enable) begin
            mem_out_wb_0 <= mem_out_mw_0;
            alu_out_wb <= alu_out_mw;
            reg_wr_en_wb <= reg_wr_en_mw;
            instr_wb <= instr_mw;
            wb_sel_wb <= wb_sel_mw;
            pc_wb <= pc_mw;
        end
    end

endmodule