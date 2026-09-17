module hazard_detect(
    input logic clk, rst_n,
    input logic [12:0] instr_em, instr_mw, instr_fd, instr_de,
    input read_finish, write_finish, empty, full, rd_en, wr_en, tmatmul_assert, almost_empty, almost_full,
    output logic em_stall, mw_stall, fd_stall, de_stall, pc_stall, flush_wb
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
		
	logic hazard_0, hazard_1, hazard_2, hazard_3;
    // assign hazard_0 = instr_mw[12-:4] == TMATMUL && (instr_em[12-:4] == LDV || instr_em[12-:4] == TMATMUL) 
    //MEMORY HAZARD TMATMUL
    // assign hazard_0 = (instr_mw[12-:4] == TMATMUL) && !read_finish;
    assign hazard_0 = tmatmul_assert & (instr_em[12-:4] == LDV | instr_em[12-:4] == STV | instr_em[12-:4] == '1) & !read_finish;
    //DATA HAZARD
    always_comb begin
        if(instr_de[12-:4] == STV || instr_de[12-:4] == LDV)
            hazard_1 = (!almost_empty && rd_en) || (!almost_full && wr_en );
        else
            hazard_1 = !almost_empty && rd_en;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            hazard_2 <= 1'b0;
        end else begin
            // Hazard 2 is set when the instruction in the EM stage is a load/store and the write operation is not finished
            hazard_2 <= !(write_finish | full) & (&instr_em[12-:4]);
        end
    end
    // always_comb begin
    //     hazard_2 = !(write_finish | full) & (&instr_em[12-:4]);
    // end

    always_comb begin
        hazard_3 = &instr_fd[12-:4];
    end

    always_comb begin
        case({hazard_0, hazard_1})
            2'b01: begin
                pc_stall = 1'b0;
                fd_stall = 1'b0;
                de_stall = 1'b1;
                em_stall = 1'b1;
                mw_stall = 1'b1;
            end
            2'b10, 2'b11: begin
                em_stall = 1'b0;
                fd_stall = 1'b0;
                de_stall = 1'b0;
                mw_stall = 1'b1;
                pc_stall = 1'b0;
            end
            default: begin
                fd_stall = 1'b1;
                de_stall = 1'b1;
                em_stall = 1'b1;
                mw_stall = 1'b1  & !hazard_2;
                pc_stall = 1'b1 & !hazard_3;
            end
        endcase
    end

    always_comb begin
        if (tmatmul_assert && (instr_em[12-:4] == LDV | instr_em[12-:4] == STV)) begin
            flush_wb = 1'b1;
        end else begin
            flush_wb = 1'b0;
        end
    end

endmodule

