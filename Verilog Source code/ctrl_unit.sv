module ctrl_unit(
    input logic [12:0] instr,
    output logic reg_wr_en,
    output logic reg_rd_en,
    output logic [2:0] alu_op,
    output logic mem_wren,
    output logic mem_rden_0,
    output logic mem_rden_1,
    output logic wb_sel,
    output logic unsupported
);
    localparam logic [3:0] ADD = 4'h1, SUB = 4'h2, MUL = 4'h3, DIV_OP = 4'h4, EXP_OP = 4'h5, SIG = 4'h6, NORM = 4'h7, TMATMUL = 4'h8, LDV = 4'h9, STV = 4'ha;
    always_comb begin
        reg_wr_en = 0;reg_rd_en = 0;alu_op = 0;mem_wren = 0;mem_rden_0 = 0;mem_rden_1 = 0;wb_sel = 0;unsupported = 0;
        case (instr[12:9])
            ADD, SUB, MUL, SIG : begin reg_wr_en = 1;reg_rd_en = 1;alu_op = instr[11:9];end
            NORM : begin reg_wr_en = 1;reg_rd_en = 1;alu_op = 3'b111;end
            TMATMUL : begin reg_wr_en = 1;reg_rd_en = 1;end
            LDV, STV, DIV_OP, EXP_OP : unsupported = 1;
            default : ;
        endcase
    end
endmodule
