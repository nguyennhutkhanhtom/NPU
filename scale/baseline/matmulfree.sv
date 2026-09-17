module matmulfree(
    input  logic rst_n, clk,
    output logic ready, overflow_out, carry_out,
    output logic [8:0] pc_debug,
    output logic [12:0] instr_debug,
    output logic [511:0] mem_out_1_debug
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
    
    
//    logic clk;
    // Pipeline control signals
    logic pc_stall, em_stall, mw_stall, fd_stall, de_stall;
    logic write_finish, read_finish;
    logic reg_wr_en_de, reg_wr_en_wb, reg_rd_en_de;
    logic mem_wr_en_de, mem_rd_en_de_0, mem_rd_en_de_1;
    logic tmatmul_assert;

    // Instruction pipeline registers
    logic [12:0] instr_fd, instr_de, instr_em, instr_mw, instr_wb;

    // Program Counter and Hazard Detection
    logic [8:0] pc, pc_de;
    logic empty, full, almost_empty, almost_full;
    logic flush_wb;
	
    hazard_detect hazard_detect_inst (
        .clk(clk), .rst_n(rst_n),
        .instr_fd(instr_fd), .instr_de(instr_de), .instr_em(instr_em), .instr_mw(instr_mw), 
        .almost_empty(almost_empty), .almost_full(almost_full), .read_finish(read_finish), .write_finish(write_finish),
        .empty(empty), .full(full),
        .tmatmul_assert(tmatmul_assert),
        .rd_en(reg_rd_en_de), .wr_en(reg_wr_en_de),
        .em_stall(em_stall), .mw_stall(mw_stall), .fd_stall(fd_stall),
        .de_stall(de_stall), .pc_stall(pc_stall),
        .flush_wb(flush_wb)
    );

    PC PC(
        .clk(clk), .rst(rst_n),
        .pc_out(pc), .stall(pc_stall)
    );

    // instr[12-:4] is the opcode
    // instr[2-0] is the source register 1
    // instr[5-3] is the source register 2
    // instr[8-6] is the destination register
    ins_mem ins_mem(
        .clk(clk),
        .addr(pc),
        .instr(instr_fd)
    );

    fd_reg fd_reg_inst (
        .clk(clk), .rst_n(rst_n), .enable(fd_stall),
        .instr_fd(instr_fd), .instr_de(instr_de), 
        .pc(pc), .pc_de(pc_de)
    );

    // Decode Stage
    
    logic [511:0] reg_out_0_de, reg_out_1_de;
    logic [2:0] alu_op_de;
    logic wb_sel_de;

    logic [511:0] reg_out_0_em, reg_out_1_em;
    logic reg_wr_en_em, mem_wr_en_em, mem_rd_en_em_0, mem_rd_en_em_1;
    logic [2:0] alu_op_em;
    logic wb_sel_em;
    logic [511:0] wb_data;
    logic [8:0] pc_em;  
    
    ctrl_unit ctrl_unit_inst (
        .instr(instr_de),
        .reg_wr_en(reg_wr_en_de), .reg_rd_en(reg_rd_en_de),
        .mem_wren(mem_wr_en_de), .mem_rden_0(mem_rd_en_de_0), .mem_rden_1(mem_rd_en_de_1),
        .alu_op(alu_op_de), .wb_sel(wb_sel_de)
    );
        
    register register_inst (
        .clk(clk), .rst_n(rst_n), .data_in(wb_data), 
        .r_addr_0(instr_de[2:0]), .r_addr_1(instr_de[5:3]),
        .w_addr(instr_wb[8:6]), .w_en(reg_wr_en_wb), .rd_en(reg_rd_en_de),
        .full(full), .empty(empty), .almost_full(almost_full), .almost_empty(almost_empty),
        .data_out_0(reg_out_0_de), .data_out_1(reg_out_1_de)
    );

    de_reg de_reg_inst (
        .clk(clk), .rst_n(rst_n), .enable(de_stall),
        .instr_de(instr_de), .reg_out_0_de(reg_out_0_de), .reg_out_1_de(reg_out_1_de),
        .reg_wr_en_de(reg_wr_en_de), .mem_wr_en_de(mem_wr_en_de),
        .mem_rd_en_de_0(mem_rd_en_de_0), .mem_rd_en_de_1(mem_rd_en_de_1),
        .alu_op_de(alu_op_de), .wb_sel_de(wb_sel_de), .pc_de(pc_de),
        .instr_em(instr_em), .reg_out_0_em(reg_out_0_em), .reg_out_1_em(reg_out_1_em),
        .reg_wr_en_em(reg_wr_en_em), .mem_wr_en_em(mem_wr_en_em),
        .mem_rd_en_em_0(mem_rd_en_em_0), .mem_rd_en_em_1(mem_rd_en_em_1),
        .alu_op_em(alu_op_em), .wb_sel_em(wb_sel_em), .pc_em(pc_em)
    );

    //execute and memory access
    logic [15:0] alu_in_a[31:0], alu_in_b[31:0], alu_out_array [31:0];
    logic carry, overflow;
    logic [511:0] alu_out_em;
    
    logic [511:0] alu_out_mw;
    logic [511:0] reg_out_0_mw;
    logic reg_wr_en_mw, mem_wr_en_mw, mem_rd_en_mw_0, mem_rd_en_mw_1;
    logic wb_sel_mw;
    logic [8:0] pc_mw;

    always_comb begin
        for(int i = 0; i < 32; i = i + 1) begin
            alu_in_a[i] = reg_out_0_em[16*i +: 16];
            alu_in_b[i] = reg_out_1_em[16*i +: 16];
        end
        // {alu_in_a[31], alu_in_a[30], alu_in_a[29], alu_in_a[28], alu_in_a[27], alu_in_a[26], alu_in_a[25], alu_in_a[24],
        //  alu_in_a[23], alu_in_a[22], alu_in_a[21], alu_in_a[20], alu_in_a[19], alu_in_a[18], alu_in_a[17], alu_in_a[16],
        //  alu_in_a[15], alu_in_a[14], alu_in_a[13], alu_in_a[12], alu_in_a[11], alu_in_a[10], alu_in_a[9], alu_in_a[8],
        //  alu_in_a[7], alu_in_a[6], alu_in_a[5], alu_in_a[4], alu_in_a[3], alu_in_a[2], alu_in_a[1], alu_in_a[0]} = reg_out_0_em;
        // {alu_in_b[31], alu_in_b[30], alu_in_b[29], alu_in_b[28], alu_in_b[27], alu_in_b[26], alu_in_b[25], alu_in_b[24],
        //  alu_in_b[23], alu_in_b[22], alu_in_b[21], alu_in_b[20], alu_in_b[19], alu_in_b[18], alu_in_b[17], alu_in_b[16],
        //  alu_in_b[15], alu_in_b[14], alu_in_b[13], alu_in_b[12], alu_in_b[11], alu_in_b[10], alu_in_b[9], alu_in_b[8],
        //  alu_in_b[7], alu_in_b[6], alu_in_b[5], alu_in_b[4], alu_in_b[3], alu_in_b[2], alu_in_b[1], alu_in_b[0]} = reg_out_1_em;
    end

    rowwise_op rowwise_op_inst (
        .a(alu_in_a), .b(alu_in_b), .alu_out(alu_out_array),
        .carry_out(carry), .overflow(overflow), .select(alu_op_em)
    );

    assign overflow_out = overflow;
    assign carry_out = carry;
    
    always_comb begin
        alu_out_em = {alu_out_array[31], alu_out_array[30], alu_out_array[29], alu_out_array[28], alu_out_array[27], alu_out_array[26],
                        alu_out_array[25], alu_out_array[24], alu_out_array[23], alu_out_array[22], alu_out_array[21], alu_out_array[20],
                        alu_out_array[19], alu_out_array[18], alu_out_array[17], alu_out_array[16], alu_out_array[15], alu_out_array[14],
                        alu_out_array[13], alu_out_array[12], alu_out_array[11], alu_out_array[10], alu_out_array[9], alu_out_array[8],
                        alu_out_array[7], alu_out_array[6], alu_out_array[5], alu_out_array[4], alu_out_array[3], alu_out_array[2],
                        alu_out_array[1], alu_out_array[0]};
        // alu_out_em = {alu_out_array[3], alu_out_array[2], alu_out_array[1], alu_out_array[0]};
    end

    em_reg em_reg_inst (
        .clk(clk), .rst_n(rst_n), .enable(em_stall),
        .instr_em(instr_em), .alu_out_em(alu_out_em),
        .reg_out_0_em(reg_out_0_em), .reg_wr_en_em(reg_wr_en_em),
        .mem_wr_en_em(mem_wr_en_em), .mem_rd_en_em_0(mem_rd_en_em_0),
        .mem_rd_en_em_1(mem_rd_en_em_1), .wb_sel_em(wb_sel_em), .pc_em(pc_em),
        .instr_mw(instr_mw), .alu_out_mw(alu_out_mw),
        .reg_out_0_mw(reg_out_0_mw), .reg_wr_en_mw(reg_wr_en_mw),
        .mem_wr_en_mw(mem_wr_en_mw), .mem_rd_en_mw_0(mem_rd_en_mw_0),
        .mem_rd_en_mw_1(mem_rd_en_mw_1), .wb_sel_mw(wb_sel_mw), .pc_mw(pc_mw)
    );

    // memmory to write back
    logic [511:0] mem_out_0_mw, mem_out_1_mw, mem_in;
    logic [511:0] alu_out_wb;
    logic [511:0] result;
    logic tmatmul_write, fifo_1_empty;
    logic [2:0] mem_r_addr_1_reg, mem_r_addr_0_reg, mem_w_addr_reg;
    logic mem_wr_en_em_reg, mem_rd_en_em_0_reg, mem_rd_en_em_1_reg;
    
    //Mux choose memory input
    logic [2:0] mem_r_addr_1_in, mem_r_addr_0_in, mem_w_addr_in;
    logic mem_wr_en_em_in, mem_rd_en_em_0_in, mem_rd_en_em_1_in;
    
    logic wb_sel_wb;
    logic [511:0] mem_out_wb;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_wr_en_em_reg <= 1'b0;
            mem_rd_en_em_0_reg <= 1'b0;
            mem_rd_en_em_1_reg <= 1'b0;
            mem_r_addr_0_reg <= 3'b0;
            mem_r_addr_1_reg <= 3'b0;
            mem_w_addr_reg <= 3'b0;
        end
        else begin 
            mem_wr_en_em_reg <= mem_wr_en_em;
            mem_rd_en_em_0_reg <= mem_rd_en_em_0;
            mem_rd_en_em_1_reg <= mem_rd_en_em_1;
            mem_r_addr_0_reg <= instr_em[2:0];
            mem_r_addr_1_reg <= instr_em[5:3];
            mem_w_addr_reg <= instr_em[8:6];
        end
    end

    //State machine for TMATMUL assertion
    localparam IDLE = 1'b0, RUN = 1'b1;
    logic tmatmul_state, next_tmatmul_state;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tmatmul_state <= IDLE;
        end
        else begin
            tmatmul_state <= next_tmatmul_state;
        end
    end

    always_comb begin
        case (tmatmul_state)
            IDLE: next_tmatmul_state = (instr_em[12-:4] == TMATMUL) ? RUN : IDLE;
            RUN:  next_tmatmul_state = (tmatmul_write) ? IDLE : RUN;
            default: next_tmatmul_state = IDLE;
        endcase
    end

    always_comb begin
        tmatmul_assert = (tmatmul_state == RUN);
    end

    // always_ff @(posedge clk or negedge rst_n) begin
    //     if (!rst_n) begin
    //         tmatmul_assert <= 1'b0;
    //     end
    //     else begin
    //         if(instr_em[12-:4] == TMATMUL) 
    //             tmatmul_assert <= 1'b1;
    //         else
    //             tmatmul_assert <= 1'b0;
    //     end
    // end  


    always_comb begin
        if(tmatmul_assert) begin
            mem_r_addr_0_in = mem_r_addr_0_reg;
            mem_r_addr_1_in = mem_r_addr_1_reg;
            mem_w_addr_in = mem_w_addr_reg;
            mem_wr_en_em_in = mem_wr_en_em_reg;
            mem_rd_en_em_0_in = mem_rd_en_em_0_reg;
            mem_rd_en_em_1_in = mem_rd_en_em_1_reg;
        end
        else begin
            mem_r_addr_0_in = instr_mw[2:0];
            mem_r_addr_1_in = instr_mw[5:3];
            mem_w_addr_in = instr_mw[8:6];
            mem_wr_en_em_in = mem_wr_en_mw;
            mem_rd_en_em_0_in = mem_rd_en_mw_0;
            mem_rd_en_em_1_in = mem_rd_en_mw_1;
        end
    end
        
    always_comb begin
        mem_in = (tmatmul_assert) ? result : reg_out_0_mw;
    end

    logic rd_type_mem;
    always_comb begin
        rd_type_mem = (tmatmul_assert);
    end
    
    mem_mapping mem_mapping_inst (
        .clk(clk), .rst_n(rst_n), .data_in(mem_in), .rd_type(rd_type_mem), .tmatmul_write(tmatmul_write),
        .r_addr_0(mem_r_addr_0_in), .r_addr_1(mem_r_addr_1_in), .w_addr(mem_w_addr_in),
        .w_en(mem_wr_en_em_in), .rd_en_0(mem_rd_en_em_0_in), .rd_en_1(mem_rd_en_em_1_in),
        // .r_addr_0(instr_mw[2:0]), .r_addr_1(instr_mw[5:3]), .w_addr(instr_mw[8:6]),
        // .w_en(mem_wr_en_mw), .rd_en_0(mem_rd_en_mw_0), .rd_en_1(mem_rd_en_mw_1),
        .read_finish(read_finish), .write_finish(write_finish), .fifo_1_empty(fifo_1_empty),
        .data_out_0(mem_out_0_mw), .data_out_1(mem_out_1_mw)
    );

    // // Ternary Multiplication
    // logic [15:0] tmatmul_in_a[31:0];
    // logic [1:0] tmatmul_in_b[31:0];

    // always_comb begin
    //     for(int i = 0; i < 32; i = i + 1) begin
    //         tmatmul_in_b[i] = mem_out_1_mw[16*i +: 16];
    //     end
    //     for(int i = 0; i < 32; i = i + 1) begin
    //         tmatmul_in_a[i] = mem_out_0_mw[16*i +: 16];
    //     end
    // end

    ternary_mul ternary_mul(
        .clk(clk),
        .rst_n(rst_n),
		.enable(tmatmul_assert),
        .matrix_in(mem_out_0_mw),
        .ternary_matrix(mem_out_1_mw),
        .matrix_out(result),
        .read_finish(read_finish),
        .tmatmul_write(tmatmul_write)
    );
    
    mw_reg mw_reg_inst (
        .clk(clk), .rst_n(rst_n), .flush(flush_wb),
        .enable(mw_stall),
        .instr_mw(instr_mw), .mem_out_mw_0(mem_out_0_mw),
        .alu_out_mw(alu_out_mw), .wb_sel_mw(wb_sel_mw), .pc_mw(pc_mw),
        .reg_wr_en_mw(reg_wr_en_mw), .instr_wb(instr_wb),
        .mem_out_wb_0(mem_out_wb), .alu_out_wb(alu_out_wb),
        .wb_sel_wb(wb_sel_wb), .reg_wr_en_wb(reg_wr_en_wb), .pc_wb(pc_debug)
    );

    assign wb_data = wb_sel_wb ? mem_out_wb : alu_out_wb;
    assign ready = &instr_wb;
    assign instr_debug = instr_wb;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_out_1_debug <= '0;
        end
        else begin
            mem_out_1_debug <= mem_out_1_mw;
        end
    end

endmodule