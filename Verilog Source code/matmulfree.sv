module matmulfree (
    input logic clk,
    input logic rst_n,

    // Simple 32-bit host window.
    input logic host_en,
    input logic host_we,
    input logic [31:0] host_addr,
    input logic [31:0] host_wdata,
    output logic [31:0] host_rdata,
    output logic host_ready,

    output logic running,
    output logic ready,
    output logic error,
    output logic overflow_out,
    output logic [8:0] pc_debug,
    output logic [12:0] instr_debug
);
    import npu_pkg::*;

    localparam logic [3:0] ADD = 4'h1, SUB = 4'h2, MUL = 4'h3, DIV_OP = 4'h4, EXP_OP = 4'h5,
    SIG = 4'h6, NORM_OP = 4'h7, TMATMUL = 4'h8, LDV = 4'h9, STV = 4'ha, REC = 4'hb, RELU = 4'hc, HALT = 4'hf;

    // ---------------- Host decode ----------------
    logic host_param, host_ws, host_desc, host_imem, host_ctrl;
    assign host_param = host_en && host_addr[31:15] == 17'h0 && host_addr[1:0] == 2'b00;
    assign host_ws = host_en && host_addr[31:13] == 19'h8 && host_addr[1:0] == 0;
    assign host_desc = host_en && host_addr[31:9] == 23'h100 && host_addr[7] == 0 && host_addr[1:0] == 0 &&
    (host_addr[8] ? host_addr[3:2] < 3 : host_addr[3:2] == 0);
    assign host_imem = host_en && host_addr[31:11] == 21'h60 && host_addr[1:0] == 0;
    assign host_ctrl = host_en && host_addr[31:8] == 24'h000400 && host_addr[1:0] == 0 &&
    (host_addr[7:2] == 0 || host_addr[7:2] == 1 ||
        (host_addr[7:2] >= 4 && host_addr[7:2] <= 10));
    logic ws_host_rvalid, p_host_rvalid;
    logic instr_fetch_en, instr_fetch_valid, instr_host_valid;
    assign host_ready = (host_ctrl && (!host_we || !running)) ||
    (!running && (host_desc || (host_imem && (host_we || instr_host_valid)) ||
        (host_param && (host_we || p_host_rvalid)) ||
        (host_ws && (host_we || ws_host_rvalid))));

    logic start_pulse;
    logic [7:0] scratch_z_base;
    logic [63:0] epsilon_raw32;
    logic [23:0] delta_raw;

    // ---------------- Program ----------------
    logic [8:0] pc;
    logic pc_clear, pc_advance;
    logic [12:0] instr_fetch, instr_q, instr_host;
    PC u_pc(.clk(clk),
        .rst_n(rst_n),
        .clear(pc_clear),
        .advance(pc_advance),
        .pc_out(pc));
    ins_mem u_imem(.clk(clk),
        .rst_n(rst_n),
        .fetch_en(instr_fetch_en),
        .addr(pc),
        .instr(instr_fetch),
        .instr_valid(instr_fetch_valid),
        .host_en(host_imem && !running),
        .host_we(host_imem && host_we && !running),
        .host_addr(host_addr[10:2]),
        .host_instr(host_wdata[12:0]),
        .host_rinstr(instr_host),
        .host_rvalid(instr_host_valid));

    // ---------------- Descriptors ----------------
    ws_desc_t d_src0, d_src1, d_dst;
    mat_desc_t d_mat, effective_mat;
    logic desc_host_matrix;
    logic [2:0] desc_host_id;
    logic [1:0] desc_host_word;
    logic [31:0] desc_host_rdata;
    assign desc_host_matrix = host_addr[8];
    assign desc_host_id = host_addr[6:4];
    assign desc_host_word = host_addr[3:2];
    descriptor_file u_desc(
        .clk(clk),
        .rst_n(rst_n),
        .host_we(host_desc && host_we && !running),
        .host_id(desc_host_id),
        .host_is_matrix(desc_host_matrix),
        .host_word_sel(desc_host_word),
        .host_wdata(host_wdata),
        .host_rdata(desc_host_rdata),
        .ws_id0(instr_q[2:0]),
        .ws_id1(instr_q[5:3]),
        .ws_id2(instr_q[8:6]),
        .ws_desc0(d_src0),
        .ws_desc1(d_src1),
        .ws_desc2(d_dst),
        .mat_id(instr_q[5:3]),
        .mat_desc(d_mat)
    );

    // ---------------- Workspace SRAM + arbitration ----------------
    logic ws_rd_en, ws_wr_en, ws_rd_valid;
    logic [7:0] ws_rd_addr, ws_wr_addr;
    logic [255:0] ws_rd_data, ws_wr_data;
    logic [31:0] ws_host_rdata;
    register u_ws(
        .clk(clk),
        .rst_n(rst_n),
        .rd_en(ws_rd_en),
        .rd_addr(ws_rd_addr),
        .rd_data(ws_rd_data),
        .rd_valid(ws_rd_valid),
        .wr_en(ws_wr_en),
        .wr_addr(ws_wr_addr),
        .wr_data(ws_wr_data),
        .host_en(host_ws && !running),
        .host_we(host_we),
        .host_addr(host_addr[12:2]),
        .host_wdata(host_wdata),
        .host_rdata(ws_host_rdata),
        .host_rvalid(ws_host_rvalid)
    );

    // ---------------- Parameter SRAM ----------------
    logic p_rd_en, p_rd_valid;
    logic [9:0] p_rd_addr;
    logic [255:0] p_rd_data;
    logic [31:0] p_host_rdata;
    mem_mapping u_param(
        .clk(clk),
        .rst_n(rst_n),
        .rd_en(p_rd_en),
        .rd_addr(p_rd_addr),
        .rd_data(p_rd_data),
        .rd_valid(p_rd_valid),
        .wr_en(1'b0),
        .wr_addr('0),
        .wr_data('0),
        .host_en(host_param && !running),
        .host_we(host_we),
        .host_addr(host_addr[14:2]),
        .host_wdata(host_wdata),
        .host_rdata(p_host_rdata),
        .host_rvalid(p_host_rvalid)
    );

    // ---------------- Row-wise vector unit ----------------
    logic row_start, row_busy, row_done, row_ov, row_fmt_err;
    logic row_rd_en, row_wr_en;
    logic [7:0] row_rd_addr, row_wr_addr;
    logic [255:0] row_wr_data;
    rowwise_dispatch u_row(
        .clk(clk),
        .rst_n(rst_n),
        .start(row_start),
        .op(instr_q[12:9]),
        .a_desc(d_src0),
        .b_desc(d_src1),
        .dst_desc(d_dst),
        .ws_rd_en(row_rd_en),
        .ws_rd_addr(row_rd_addr),
        .ws_rd_data(ws_rd_data),
        .ws_rd_valid(ws_rd_valid),
        .ws_wr_en(row_wr_en),
        .ws_wr_addr(row_wr_addr),
        .ws_wr_data(row_wr_data),
        .busy(row_busy),
        .done(row_done),
        .overflow(row_ov),
        .format_error(row_fmt_err)
    );

    // ---------------- NORM + QUANT ----------------
    logic norm_start, norm_busy, norm_done, norm_ov, norm_error;
    logic [23:0] quant_d;
    logic norm_rd_en, norm_wr_en;
    logic [7:0] norm_rd_addr, norm_wr_addr;
    logic [255:0] norm_wr_data;
    logic [23:0] norm_m, quant_m;
    logic [5:0] norm_r, quant_r;
    norm_dispatch u_norm(
        .clk(clk),
        .rst_n(rst_n),
        .start(norm_start),
        .src_desc(d_src0),
        .dst_desc(d_dst),
        .scratch_z_base(scratch_z_base),
        .epsilon_raw32(epsilon_raw32),
        .delta_raw(delta_raw),
        .ws_rd_en(norm_rd_en),
        .ws_rd_addr(norm_rd_addr),
        .ws_rd_data(ws_rd_data),
        .ws_rd_valid(ws_rd_valid),
        .ws_wr_en(norm_wr_en),
        .ws_wr_addr(norm_wr_addr),
        .ws_wr_data(norm_wr_data),
        .busy(norm_busy),
        .done(norm_done),
        .overflow(norm_ov),
        .format_error(norm_error),
        .quant_d(quant_d),
        .norm_m(norm_m),
        .norm_r(norm_r),
        .quant_m(quant_m),
        .quant_r(quant_r)
    );

    // ---------------- Ternary core ----------------
    logic tm_start, tm_busy, tm_done, tm_ov, tm_error;
    logic tm_rd_en, tm_wr_en;
    logic [7:0] tm_rd_addr, tm_wr_addr;
    logic [255:0] tm_wr_data;
    logic tm_p_rd_en;
    logic [9:0] tm_p_rd_addr;
    ternary_mul u_tm(
        .clk(clk),
        .rst_n(rst_n),
        .start(tm_start),
        .q_desc(d_src0),
        .out_desc(d_dst),
        .mat_desc(effective_mat),
        .ws_rd_en(tm_rd_en),
        .ws_rd_addr(tm_rd_addr),
        .ws_rd_data(ws_rd_data),
        .ws_rd_valid(ws_rd_valid),
        .ws_wr_en(tm_wr_en),
        .ws_wr_addr(tm_wr_addr),
        .ws_wr_data(tm_wr_data),
        .param_rd_en(tm_p_rd_en),
        .param_rd_addr(tm_p_rd_addr),
        .param_rd_data(p_rd_data),
        .param_rd_valid(p_rd_valid),
        .busy(tm_busy),
        .done(tm_done),
        .overflow(tm_ov),
        .format_error(tm_error)
    );
    assign p_rd_en = tm_p_rd_en;
    assign p_rd_addr = tm_p_rd_addr;

    // Runtime q scales are attached to the descriptor and exact memory extent.
    logic [23:0] q_d[0:7];
    logic [7:0] q_base[0:7];
    logic [9:0] q_length[0:7];
    logic [7:0] q_valid;
    logic input_has_runtime_scale;
    logic [23:0] selected_quant_d;
    logic compose_busy, compose_done, compose_error;
    logic [23:0] composed_m;
    logic [5:0] composed_r;
    typedef enum logic [3:0] {S_IDLE, S_FETCH, S_START, S_WAIT, S_ADVANCE, S_HALT,
    S_COMPOSE_START, S_COMPOSE_WAIT, S_TM_START} sched_t;
    sched_t sched;
    assign instr_fetch_en = running && sched == S_FETCH;
    logic [1:0] active_unit; // 1=row, 2=norm, 3=tm
    assign selected_quant_d = q_valid[instr_q[2:0]] ? q_d[instr_q[2:0]] : 24'h0;

    // Scale provenance belongs to the generated q memory extent. A descriptor
    // alias must not bypass the requirement to compose its runtime scale.
    always_comb begin
        input_has_runtime_scale = 1'b0;
        for (integer i = 0; i < 8; i = i + 1) begin
            if (q_valid[i]) begin
                if (ranges_overlap(int'(d_src0.base_word), ws_words(d_src0),
                    int'(q_base[i]), (int'(q_length[i]) + 31) / 32))
                    input_has_runtime_scale = 1'b1;
            end
        end
    end

    scale_compose u_compose(.clk(clk),
        .rst_n(rst_n),
        .start(sched == S_COMPOSE_START),
        .factor_m(effective_mat.scale_m),
        .factor_r(effective_mat.scale_r),
        .quant_d(selected_quant_d),
        .busy(compose_busy),
        .done(compose_done),
        .format_error(compose_error),
        .result_m(composed_m),
        .result_r(composed_r));

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            q_valid <= 0;
        end else begin
            for (integer i = 0;i < 8;i = i + 1) begin
                if (q_valid[i]) begin
                    if (ws_wr_en && int'(ws_wr_addr) >= int'(q_base[i]) &&
                        int'(ws_wr_addr) < int'(q_base[i]) + (int'(q_length[i]) + 31) / 32) q_valid[i] <= 0;
                    if (host_ws && host_we && !running && int'(host_addr[12:5]) >= int'(q_base[i]) &&
                        int'(host_addr[12:5]) < int'(q_base[i]) + (int'(q_length[i]) + 31) / 32) q_valid[i] <= 0;
                end
            end
            if (host_desc && host_we && !running) q_valid <= 0;
            if (sched == S_WAIT && active_unit == 2 && norm_done && !norm_error && !norm_ov)
                q_valid[instr_q[8:6]] <= 1;
        end
    end

    // Payload tuples are consumed only while their resettable valid bit is set.
    // Successful NORM completion writes the full tuple before making it valid.
    // Constant slot indices describe independent registers with parallel reads.
    genvar slot;
    generate
    for (slot = 0; slot < 8; slot = slot + 1) begin : g_quant_metadata
        always_ff @(posedge clk) begin
            if (rst_n && sched == S_WAIT && active_unit == 2 && norm_done &&
                !norm_error && !norm_ov && instr_q[8:6] == 3'(slot)) begin
                q_d[slot] <= quant_d;
                q_base[slot] <= d_dst.base_word;
                q_length[slot] <= d_dst.length;
            end
        end
    end
    endgenerate

    always_comb begin
        row_start = 0;
        norm_start = 0;
        tm_start = 0;
        pc_clear = (start_pulse && !running);
        pc_advance = 0;
        if (sched == S_START) begin
            case (instr_q[12:9])
                ADD, SUB, MUL, SIG, REC, RELU : row_start = 1;
                NORM_OP : norm_start = 1;
                default : ;
            endcase
        end
        if (sched == S_TM_START) tm_start = 1;
        if (sched == S_ADVANCE && pc != 9'h1ff) pc_advance = 1;
    end

    always_comb begin
        ws_rd_en = 0;
        ws_rd_addr = 0;
        ws_wr_en = 0;
        ws_wr_addr = 0;
        ws_wr_data = 0;
        case (active_unit)
            2'h1 : begin
                ws_rd_en = row_rd_en;
                ws_rd_addr = row_rd_addr;
                ws_wr_en = row_wr_en;
                ws_wr_addr = row_wr_addr;
                ws_wr_data = row_wr_data;
            end
            2'h2 : begin
                ws_rd_en = norm_rd_en;
                ws_rd_addr = norm_rd_addr;
                ws_wr_en = norm_wr_en;
                ws_wr_addr = norm_wr_addr;
                ws_wr_data = norm_wr_data;
            end
            2'h3 : begin
                ws_rd_en = tm_rd_en;
                ws_rd_addr = tm_rd_addr;
                ws_wr_en = tm_wr_en;
                ws_wr_addr = tm_wr_addr;
                ws_wr_data = tm_wr_data;
            end
            default : ;
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sched <= S_IDLE;
            instr_q <= 0;
            active_unit <= 0;
            running <= 0;
            ready <= 1;
            error <= 0;
            overflow_out <= 0;
            effective_mat <= '0;
        end else begin
            if (start_pulse && !running) begin
                running <= 1;
                ready <= 0;
                error <= 0;
                overflow_out <= 0;
                sched <= S_FETCH;
                active_unit <= 0;
            end
            case (sched)
                S_IDLE : ;
                S_FETCH : if (instr_fetch_valid) begin
                    instr_q <= instr_fetch;
                    sched <= S_START;
                end
                S_START : begin
                    case (instr_q[12:9])
                        ADD, SUB, MUL, SIG, REC, RELU : begin
                            active_unit <= 1;
                            sched <= S_WAIT;
                        end
                        NORM_OP : begin
                            active_unit <= 2;
                            sched <= S_WAIT;
                        end
                        TMATMUL : begin
                            effective_mat <= d_mat;
                            if (d_mat.reserved[0]) begin
                                if (!q_valid[instr_q[2:0]]) begin
                                    error <= 1;
                                    sched <= S_HALT;
                                end else if (q_base[instr_q[2:0]] != d_src0.base_word ||
                                             q_length[instr_q[2:0]] != d_src0.length) begin
                                    error <= 1;
                                    sched <= S_HALT;
                                end
                                else sched <= S_COMPOSE_START;
                            end else if (input_has_runtime_scale) begin
                                // NORM-generated q must consume its runtime scale.
                                error <= 1;
                                sched <= S_HALT;
                            end else sched <= S_TM_START;
                        end
                        HALT : sched <= S_HALT;
                        4'h0 : sched <= S_ADVANCE;
                        default : begin
                            error <= 1;
                            sched <= S_HALT;
                        end
                    endcase
                end
                S_WAIT : begin
                    if ((active_unit == 1 && row_done) || (active_unit == 2 && norm_done) || (active_unit == 3 && tm_done)) begin
                        if (active_unit == 1) begin
                            overflow_out <= overflow_out | row_ov;
                            error <= error | row_fmt_err;
                        end
                        if (active_unit == 2) begin
                            overflow_out <= overflow_out | norm_ov;
                            error <= error | norm_error;
                        end
                        if (active_unit == 3) begin
                            overflow_out <= overflow_out | tm_ov;
                            error <= error | tm_error;
                        end
                        active_unit <= 0;
                        sched <= S_ADVANCE;
                        if ((active_unit == 1 && row_fmt_err) || (active_unit == 2 && (norm_error || norm_ov)) ||
                            (active_unit == 3 && tm_error)) sched <= S_HALT;
                    end
                end
                S_COMPOSE_START : sched <= S_COMPOSE_WAIT;
                S_COMPOSE_WAIT : if (compose_done) begin
                    if (compose_error) begin
                        error <= 1;
                        sched <= S_HALT;
                    end
                    else begin
                        effective_mat.scale_m <= composed_m;
                        effective_mat.scale_r <= composed_r;
                        sched <= S_TM_START;
                    end
                end
                S_TM_START : begin
                    active_unit <= 3;
                    sched <= S_WAIT;
                end
                S_ADVANCE : if (pc == 9'h1ff) begin
                    error <= 1;
                    sched <= S_HALT;
                end else sched <= S_FETCH;
                S_HALT : begin
                    running <= 0;
                    ready <= 1;
                    sched <= S_IDLE;
                end
                default : sched <= S_IDLE;
            endcase
        end
    end

    assign pc_debug = pc;
    assign instr_debug = instr_q;

    always_comb begin
        host_rdata = 32'h0000_0000;
        if (host_param) host_rdata = p_host_rdata;
        else if (host_ws) host_rdata = ws_host_rdata;
        else if (host_desc) host_rdata = desc_host_rdata;
        else if (host_imem) host_rdata = {19'h0, instr_host};
        else if (host_ctrl) begin
            case (host_addr[7:2])
                6'h00 : host_rdata = {28'h0, error, overflow_out, ready, running};
                6'h01 : host_rdata = {23'h0, pc};
                6'h04 : host_rdata = {24'h00_0000, scratch_z_base};
                6'h05 : host_rdata = epsilon_raw32[31:0];
                6'h06 : host_rdata = epsilon_raw32[63:32];
                6'h07 : host_rdata = {8'h00, delta_raw};
                6'h08 : host_rdata = {2'h0, quant_r, quant_m};
                6'h09 : host_rdata = {2'h0, norm_r, norm_m};
                6'h0a : host_rdata = {8'h00, quant_d};
                default : host_rdata = 0;
            endcase
        end
    end

    assign start_pulse = host_ctrl && host_we && (host_addr[7:2] == 0) && host_wdata[0];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scratch_z_base <= 8'h80;
            epsilon_raw32 <= 0;
            delta_raw <= 24'h00_0001;
        end else if (host_ctrl && host_we && !running) begin
            case (host_addr[7:2])
                6'h04 : scratch_z_base <= host_wdata[7:0];
                6'h05 : epsilon_raw32[31:0] <= host_wdata;
                6'h06 : epsilon_raw32[63:32] <= host_wdata;
                6'h07 : delta_raw <= host_wdata[23:0];
                default : ;
            endcase
        end
    end
endmodule
