module ternary_mul (
    input logic clk,
    input logic rst_n,
    input logic start,
    input npu_pkg::ws_desc_t q_desc,
    input npu_pkg::ws_desc_t out_desc,
    input npu_pkg::mat_desc_t mat_desc,

    output logic ws_rd_en,
    output logic [7:0] ws_rd_addr,
    input logic [255:0] ws_rd_data,
    input logic ws_rd_valid,
    output logic ws_wr_en,
    output logic [7:0] ws_wr_addr,
    output logic [255:0] ws_wr_data,

    output logic param_rd_en,
    output logic [9:0] param_rd_addr,
    input logic [255:0] param_rd_data,
    input logic param_rd_valid,

    output logic busy,
    output logic done,
    output logic overflow,
    output logic format_error
);
    import npu_pkg::*;
    typedef enum logic [3:0] {IDLE, REQ_CHUNK, WAIT_CHUNK, ACCUM, REQ_BIAS, WAIT_BIAS, SCALE, WRITE, FINISH} state_t;
    state_t state;

    ws_desc_t input_desc_q, output_desc_q;
    mat_desc_t matrix_desc_q;
    logic [9:0] output_row_q, input_chunk_q;
    logic [9:0] chunks_per_row;
    logic [9:0] weight_words_per_row;
    logic [255:0] q_word, w_word;
    logic got_q, got_w;
    logic signed [17:0] accumulator_q;
    logic signed [8:0] terms [0:31];
    logic signed [17:0] partial;
    logic [7:0] weight_bit_base;
    logic reserved_weight;

    logic signed [31:0] bias;
    logic signed [31:0] y32;
    logic signed [15:0] y16;
    logic scale_ov;
    postscale u_scale(.acc(accumulator_q),
        .scale_m(matrix_desc_q.scale_m),
        .scale_r(matrix_desc_q.scale_r),
        .bias(bias),
        .output_s32(matrix_desc_q.output_s32),
        .y_s32(y32),
        .y_s16(y16),
        .overflow(scale_ov));

    logic [255:0] pack_buf;
    logic [4:0] pack_count;
    logic [7:0] out_word;

    always_comb begin
        weight_bit_base = {input_chunk_q[1:0], 6'b0};
        reserved_weight = 0;
        for (int i = 0;i < 32;i = i + 1) begin
            logic signed [7:0] a;
            logic [1:0] w;
            a = q_word[i * 8 +: 8];
            w = w_word[weight_bit_base + i * 2 +: 2];
            if ((input_chunk_q * 32 + i) >= matrix_desc_q.k_len) terms[i] = 9'sh000;
            else begin
                if (w == 2'b10) reserved_weight = 1;
                case (w)
                    2'b01 : terms[i] = {a[7], a};
                    2'b11 : terms[i] = - $signed({a[7], a});
                    default : terms[i] = 9'sh000; // 00=0, 10 reserved -> 0
                endcase
            end
        end
    end
    acc_mul #(.TERM_W(9),
        .NUM_INPUTS(32),
        .ACC_W(18)) u_reduce(.term(terms),
        .sum(partial));

    always_comb begin
        ws_rd_en = 0;
        ws_rd_addr = '0;
        ws_wr_en = 0;
        ws_wr_addr = '0;
        ws_wr_data = pack_buf;
        param_rd_en = 0;
        param_rd_addr = '0;
        if (state == REQ_CHUNK) begin
            ws_rd_en = 1;
            ws_rd_addr = input_desc_q.base_word + input_chunk_q[7:0];
            param_rd_en = (input_chunk_q[1:0] == 0);
            param_rd_addr = matrix_desc_q.weight_base + output_row_q * weight_words_per_row + (input_chunk_q >> 2);
        end else if (state == REQ_BIAS) begin
            param_rd_en = 1;
            param_rd_addr = matrix_desc_q.bias_base + (output_row_q >> 3);
        end else if (state == WRITE) begin
            ws_wr_en = 1;
            ws_wr_addr = output_desc_q.base_word + out_word;
            ws_wr_data = pack_buf;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            busy <= 0;
            done <= 0;
            overflow <= 0;
            format_error <= 0;
            input_desc_q <= '0;
            output_desc_q <= '0;
            matrix_desc_q <= '0;
            output_row_q <= 0;
            input_chunk_q <= 0;
            chunks_per_row <= 0;
            weight_words_per_row <= 0;
            q_word <= 0;
            w_word <= 0;
            got_q <= 0;
            got_w <= 0;
            accumulator_q <= 0;
            bias <= 0;
            pack_buf <= 0;
            pack_count <= 0;
            out_word <= 0;
        end else begin
            done <= 0;
            case (state)
                IDLE : if (start) begin
                    busy <= 1;
                    overflow <= 0;
                    format_error <= 0;
                    input_desc_q <= q_desc;
                    output_desc_q <= out_desc;
                    matrix_desc_q <= mat_desc;
                    output_row_q <= 0;
                    input_chunk_q <= 0;
                    accumulator_q <= 0;
                    chunks_per_row <= 10'((mat_desc.k_len + 31) >> 5);
                    weight_words_per_row <= 10'((mat_desc.k_len + 127) >> 7);
                    pack_buf <= 0;
                    pack_count <= 0;
                    out_word <= 0;
                    got_q <= 0;
                    got_w <= 0;
                    state <= REQ_CHUNK;
                    if (!ws_valid(q_desc) || !ws_valid(out_desc) || q_desc.fmt != FMT_S8 ||
                        out_desc.fmt != (mat_desc.output_s32 ? FMT_S32 : FMT_S16) ||
                        mat_desc.k_len == 0 || mat_desc.k_len > K_MAX || mat_desc.n_rows == 0 ||
                        q_desc.length != mat_desc.k_len || out_desc.length != mat_desc.n_rows ||
                        mat_desc.scale_r > 47 ||
                        int'(mat_desc.weight_base) + int'(mat_desc.n_rows) * ((int'(mat_desc.k_len) + 127) / 128) > 1024 ||
                        (!mat_desc.reserved[1] && int'(mat_desc.bias_base) + (int'(mat_desc.n_rows) + 7) / 8 > 1024) ||
                        ranges_overlap(int'(q_desc.base_word), ws_words(q_desc), int'(out_desc.base_word), ws_words(out_desc))) begin
                        format_error <= 1;
                        state <= FINISH;
                    end
                end
                REQ_CHUNK : begin
                    got_q <= 0;
                    got_w <= (input_chunk_q[1:0] != 0);
                    state <= WAIT_CHUNK;
                end
                WAIT_CHUNK : begin
                    if (ws_rd_valid) begin
                        q_word <= ws_rd_data;
                        got_q <= 1;
                    end
                    if (param_rd_valid) begin
                        w_word <= param_rd_data;
                        got_w <= 1;
                    end
                    if ((got_q || ws_rd_valid) && (got_w || param_rd_valid)) state <= ACCUM;
                end
                ACCUM : begin
                    if (input_chunk_q + 1 >= chunks_per_row) begin
                        accumulator_q <= accumulator_q + partial;
                        input_chunk_q <= 0;
                        if (matrix_desc_q.reserved[1]) begin
                            bias <= 0;
                            state <= SCALE;
                        end
                        else state <= REQ_BIAS;
                    end else begin
                        accumulator_q <= accumulator_q + partial;
                        input_chunk_q <= input_chunk_q + 1'b1;
                        state <= REQ_CHUNK;
                    end
                    if (reserved_weight) begin
                        format_error <= 1;
                        state <= FINISH;
                    end
                end
                REQ_BIAS : state <= WAIT_BIAS;
                WAIT_BIAS : if (param_rd_valid) begin
                    bias <= param_rd_data[(output_row_q[2:0] * 32) +: 32];
                    state <= SCALE;
                end
                SCALE : begin
                    overflow <= overflow | scale_ov;
                    if (matrix_desc_q.output_s32) begin
                        pack_buf[pack_count * 32 +: 32] <= y32;
                        if (pack_count == 7 || output_row_q + 1 >= matrix_desc_q.n_rows) state <= WRITE;
                        else begin
                            pack_count <= pack_count + 1'b1;
                            output_row_q <= output_row_q + 1'b1;
                            accumulator_q <= 0;
                            state <= REQ_CHUNK;
                        end
                    end else begin
                        pack_buf[pack_count * 16 +: 16] <= y16;
                        if (pack_count == 15 || output_row_q + 1 >= matrix_desc_q.n_rows) state <= WRITE;
                        else begin
                            pack_count <= pack_count + 1'b1;
                            output_row_q <= output_row_q + 1'b1;
                            accumulator_q <= 0;
                            state <= REQ_CHUNK;
                        end
                    end
                end
                WRITE : begin
                    pack_buf <= 0;
                    pack_count <= 0;
                    out_word <= out_word + 1'b1;
                    if (output_row_q + 1 >= matrix_desc_q.n_rows) state <= FINISH;
                    else begin
                        output_row_q <= output_row_q + 1'b1;
                        accumulator_q <= 0;
                        state <= REQ_CHUNK;
                    end
                end
                FINISH : begin
                    busy <= 0;
                    done <= 1;
                    state <= IDLE;
                end
                default : state <= IDLE;
            endcase
        end
    end
endmodule
