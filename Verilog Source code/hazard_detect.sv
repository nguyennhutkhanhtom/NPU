module hazard_detect(
    input logic clk, rst_n,
    input logic [12:0] instr_em, instr_mw, instr_fd, instr_de,
    input read_finish, write_finish, empty, full, rd_en, wr_en, tmatmul_assert, almost_empty, almost_full,
    output logic em_stall, mw_stall, fd_stall, de_stall, pc_stall, flush_wb,
    input logic register_read_last, transactions_busy,
    output logic decode_bubble
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
		
    logic hazard_0, hazard_1, hazard_3;
    // The caller includes the TM start cycle in tmatmul_assert. Hold conflicting
    // instructions BEFORE they start a register stream or enter the memory path.
    // read_finish is not completion: the engine may still compute/write results.
    assign hazard_0 = (tmatmul_assert &&
        (instr_de[12:9] == LDV || instr_de[12:9] == STV ||
         instr_de[12:9] == TMATMUL || instr_de[12:9] == 4'hf)) ||
        // A new TM must also wait for older normal memory/register streams.
        (instr_de[12:9] == TMATMUL &&
         (transactions_busy || instr_em[12:9] == LDV || instr_em[12:9] == STV ||
          instr_mw[12:9] == LDV || instr_mw[12:9] == STV));
    assign decode_bubble = hazard_0;
    //DATA HAZARD
    always_comb begin
        if(instr_de[12-:4] == STV || instr_de[12-:4] == LDV)
            hazard_1 = (!register_read_last && rd_en) || (!almost_full && wr_en );
        else
            // Retain the operation until the actual final source word is
            // sampled. Releasing at word 12 drops three words before NORM/NOP.
            hazard_1 = !register_read_last && rd_en;
    end

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
                // Drain older operations exactly once; inject a NOP from DE.
                em_stall = 1'b1;
                fd_stall = 1'b0;
                de_stall = 1'b1;
                mw_stall = 1'b1;
                pc_stall = 1'b0;
            end
            default: begin
                fd_stall = 1'b1;
                de_stall = 1'b1;
                em_stall = 1'b1;
                // HALT must not retain an older WB write-enable: doing so can
                // restart a completed vector write. The top-level ready waits
                // for all outstanding transactions after HALT reaches WB.
                mw_stall = 1'b1;
                pc_stall = 1'b1 & !hazard_3;
            end
        endcase
    end

    // No younger memory instruction reaches WB while blocked at decode.
    // Flushing WB here would discard the older ALU operation being drained.
    assign flush_wb = 1'b0;

endmodule

