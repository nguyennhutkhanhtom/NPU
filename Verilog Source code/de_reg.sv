module de_reg(
    input logic clk, rst_n, enable, flush,
    input logic [12:0] instr_de,
    input logic [255:0] reg_out_0_de, reg_out_1_de,
    input logic reg_wr_en_de, mem_wr_en_de, mem_rd_en_de_0, mem_rd_en_de_1,
    input logic [2:0] alu_op_de, input logic wb_sel_de, input logic [8:0] pc_de,
    output logic [12:0] instr_em,
    output logic [255:0] reg_out_0_em, reg_out_1_em,
    output logic reg_wr_en_em, mem_wr_en_em, mem_rd_en_em_0, mem_rd_en_em_1,
    output logic [2:0] alu_op_em, output logic wb_sel_em, output logic [8:0] pc_em
);
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || flush) begin instr_em <= 0;reg_out_0_em <= 0;reg_out_1_em <= 0;reg_wr_en_em <= 0;mem_wr_en_em <= 0;mem_rd_en_em_0 <= 0;mem_rd_en_em_1 <= 0;alu_op_em <= 0;wb_sel_em <= 0;pc_em <= 0;end
        else if (enable) begin instr_em <= instr_de;reg_out_0_em <= reg_out_0_de;reg_out_1_em <= reg_out_1_de;reg_wr_en_em <= reg_wr_en_de;mem_wr_en_em <= mem_wr_en_de;mem_rd_en_em_0 <= mem_rd_en_de_0;mem_rd_en_em_1 <= mem_rd_en_de_1;alu_op_em <= alu_op_de;wb_sel_em <= wb_sel_de;pc_em <= pc_de;end
    end
endmodule
