module ctrl_unit(
    input logic [12:0] instr,

    output logic       reg_wr_en,
    output logic       reg_rd_en,
    output logic [2:0] alu_op,
    output logic       mem_wren, mem_rden_0, mem_rden_1,
    output logic       wb_sel               //0: alu, 1: mem
);

    localparam ADD = 4'b0001;
    localparam SUB = 4'b0010;
    localparam MUL = 4'b0011;
    localparam DIV = 4'b0100;
    localparam EXP = 4'b0101;
    localparam SIG = 4'b0110;
    localparam NORM = 4'b0111;
    localparam TMATMUL = 4'b1000;
    localparam LDV = 4'b1001;
    localparam STV = 4'b1010;

    always_comb begin
        casex(instr[12-:4])
            LDV: begin
                reg_wr_en = 1'b1;
                reg_rd_en = 1'b0;
                alu_op = 3'b000;
                mem_wren = 1'b0;
                mem_rden_0 = 1'b1;
                mem_rden_1 = 1'b0;
                wb_sel = 1'b1;
            end
            STV: begin
                reg_wr_en = 1'b0;
                reg_rd_en = 1'b1;
                alu_op = 3'b000;
                mem_wren = 1'b1;
                mem_rden_0 = 1'b0;
                mem_rden_1 = 1'b0;
                wb_sel = 1'b1;
            end
            TMATMUL: begin
                reg_wr_en = 1'b0;
                reg_rd_en = 1'b0;
                alu_op = 3'b000;
                mem_wren = 1'b1;
                mem_rden_0 = 1'b1;
                mem_rden_1 = 1'b1;
                wb_sel = 1'b0;
            end
            ADD, SUB, MUL, DIV, EXP, SIG, NORM: begin
                reg_wr_en = 1'b1;
                reg_rd_en = 1'b1;
                alu_op = instr[11:9];
                mem_wren = 1'b0;
                mem_rden_0 = 1'b0;
                mem_rden_1 = 1'b0;
                wb_sel = 1'b0;
            end
            default: begin
                reg_wr_en = 1'b0;
                reg_rd_en = 1'b0;
                alu_op = 3'b000;
                mem_wren = 1'b0;
                mem_rden_0 = 1'b0;
                mem_rden_1 = 1'b0;
                wb_sel = 1'b0;
            end
        endcase
    end

endmodule