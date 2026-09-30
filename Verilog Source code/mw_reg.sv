module mw_reg(
    input logic clk, rst_n, enable, flush, input logic [12:0] instr_mw,
    input logic [255:0] mem_out_mw_0, alu_out_mw, input logic wb_sel_mw, reg_wr_en_mw, input logic [8:0] pc_mw,
    output logic [12:0] instr_wb, output logic [255:0] mem_out_wb_0, alu_out_wb, output logic reg_wr_en_wb, wb_sel_wb, output logic [8:0] pc_wb
);
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || flush) begin instr_wb <= 0;mem_out_wb_0 <= 0;alu_out_wb <= 0;reg_wr_en_wb <= 0;wb_sel_wb <= 0;pc_wb <= 0;end
        else if (enable) begin instr_wb <= instr_mw;mem_out_wb_0 <= mem_out_mw_0;alu_out_wb <= alu_out_mw;reg_wr_en_wb <= reg_wr_en_mw;wb_sel_wb <= wb_sel_mw;pc_wb <= pc_mw;end
    end
endmodule
