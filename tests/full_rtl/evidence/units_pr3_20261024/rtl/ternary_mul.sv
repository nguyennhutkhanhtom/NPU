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
    typedef enum logic [3:0] {IDLE, REQ_CHUNK, WAIT_CHUNK, REDUCE_GROUPS, REDUCE_TOTAL, ACCUM, REQ_BIAS, WAIT_BIAS,
        SCALE_PRODUCT, SCALE_ROUND, SCALE, WRITE, FINISH} state_t;
    state_t state;

    ws_desc_t input_desc_q, output_desc_q;
    mat_desc_t matrix_desc_q;
    logic [9:0] output_row_q, input_chunk_q;
    logic [9:0] chunks_per_row;
    logic [2:0] weight_words_per_row, weight_stride_next;
    logic [11:0] weight_extent;
    logic [9:0] weight_row_addr_q;
    logic [255:0] q_word, w_word;
    logic got_q, got_w;
    logic signed [17:0] accumulator_q;
    logic signed [8:0] terms [0:31];
    logic signed [17:0] partial;
    logic signed [8:0] group_terms [0:3][0:7];
    logic signed [11:0] group_sum [0:3], group_sum_q [0:3];
    logic signed [13:0] total_sum, total_sum_q;
    logic reserved_weight_q;
    logic [7:0] weight_bit_base;
    logic reserved_weight;

    logic signed [31:0] bias;
    logic signed [31:0] y32;
    logic signed [15:0] y16;
    logic scale_ov;
    logic signed [41:0] scale_product_q, scale_rounded_q;
    wire [41:0] scale_product_comb;
    logic_mul #(.A_W(18), .B_W(24), .OUT_W(42), .SIGNED_A(1), .SIGNED_B(0)) u_bit_mul
        (.a(accumulator_q), .b(matrix_desc_q.scale_m), .product(scale_product_comb));

    // Payload registers have no asynchronous reset. SCALE is reachable only
    // after both stages have captured this row; reset cancels the control FSM.
    always_ff @(posedge clk) begin
        if (rst_n && state == SCALE_PRODUCT)
            scale_product_q <= scale_product_comb;
        if (rst_n && state == SCALE_ROUND)
            scale_rounded_q <= rne_shift42(scale_product_q, matrix_desc_q.scale_r);
    end
    postscale_finish u_scale(.rounded(scale_rounded_q),
        .bias(bias),
        .output_s32(matrix_desc_q.output_s32),
        .y_s32(y32),
        .y_s16(y16),
        .overflow(scale_ov));

    logic [255:0] pack_buf;
    logic [4:0] pack_count;
    logic [7:0] out_word;

    // Validated K is 1..512, so each row occupies one to four weight words.
    // Shift/add bounds checking and a row pointer avoid two address multipliers.
    always_comb begin
        weight_stride_next = 3'(((int'(mat_desc.k_len) + 127) >> 7));
        case (weight_stride_next)
            3'd1 : weight_extent = {2'b0, mat_desc.n_rows};
            3'd2 : weight_extent = {1'b0, mat_desc.n_rows, 1'b0};
            3'd3 : weight_extent = {1'b0, mat_desc.n_rows, 1'b0} + {2'b0, mat_desc.n_rows};
            3'd4 : weight_extent = {mat_desc.n_rows, 2'b0};
            default : weight_extent = '0; // Invalid K is rejected before any read.
        endcase
    end

    assign weight_bit_base = {input_chunk_q[1:0], 6'b0};
    wire [31:0] reserved_lane;
    genvar decode_lane;
    generate
    for (decode_lane = 0; decode_lane < 32; decode_lane = decode_lane + 1) begin : g_decode
        wire signed [7:0] lane_value = q_word[decode_lane * 8 +: 8];
        wire [1:0] lane_weight = w_word[weight_bit_base + decode_lane * 2 +: 2];
        wire lane_active = ((int'(input_chunk_q) << 5) + decode_lane) < matrix_desc_q.k_len;
        assign reserved_lane[decode_lane] = lane_active && lane_weight == 2'b10;
        always_comb begin
            terms[decode_lane] = 9'sh000;
            if (lane_active) begin
                case (lane_weight)
                    2'b01 : terms[decode_lane] = {lane_value[7], lane_value};
                    2'b11 : terms[decode_lane] = -$signed({lane_value[7], lane_value});
                    default : terms[decode_lane] = 9'sh000;
                endcase
            end
        end
    end
    endgenerate
    assign reserved_weight = |reserved_lane;
    // Four independent eight-lane trees keep carry widths proportional to
    // their ranges. Registers separate decode/reduction from accumulation.
    genvar g, lane;
    generate
    for (g = 0; g < 4; g = g + 1) begin : g_reduce
        for (lane = 0; lane < 8; lane = lane + 1) begin : g_lane
            assign group_terms[g][lane] = terms[g * 8 + lane];
        end
        always_ff @(posedge clk)
            if (rst_n && state == REDUCE_GROUPS) group_sum_q[g] <= group_sum[g];
        acc_mul #(.TERM_W(9), .NUM_INPUTS(8), .ACC_W(12)) u_group(
            .term(group_terms[g]), .sum(group_sum[g]));
    end
    endgenerate
    acc_mul #(.TERM_W(12), .NUM_INPUTS(4), .ACC_W(14)) u_total(
        .term(group_sum_q), .sum(total_sum));
    assign partial = {{4{total_sum_q[13]}}, total_sum_q};
    // Control reset cancels an in-flight chunk before these payloads are used.
    always_ff @(posedge clk) begin
        if (rst_n && state == REDUCE_GROUPS) begin
            reserved_weight_q <= reserved_weight;
        end
        if (rst_n && state == REDUCE_TOTAL) total_sum_q <= total_sum;
    end

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
            param_rd_addr = weight_row_addr_q + (input_chunk_q >> 2);
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
            weight_row_addr_q <= 0;
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
                    weight_words_per_row <= weight_stride_next;
                    weight_row_addr_q <= mat_desc.weight_base;
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
                        int'(mat_desc.weight_base) + int'(weight_extent) > 1024 ||
                        (!mat_desc.reserved[1] && int'(mat_desc.bias_base) + ((int'(mat_desc.n_rows) + 7) >> 3) > 1024) ||
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
                    if ((got_q || ws_rd_valid) && (got_w || param_rd_valid)) state <= REDUCE_GROUPS;
                end
                REDUCE_GROUPS : state <= REDUCE_TOTAL;
                REDUCE_TOTAL : state <= ACCUM;
                ACCUM : begin
                    if (input_chunk_q + 1 >= chunks_per_row) begin
                        accumulator_q <= accumulator_q + partial;
                        input_chunk_q <= 0;
                        if (matrix_desc_q.reserved[1]) begin
                            bias <= 0;
                            state <= SCALE_PRODUCT;
                        end
                        else state <= REQ_BIAS;
                    end else begin
                        accumulator_q <= accumulator_q + partial;
                        input_chunk_q <= input_chunk_q + 1'b1;
                        state <= REQ_CHUNK;
                    end
                    if (reserved_weight_q) begin
                        format_error <= 1;
                        state <= FINISH;
                    end
                end
                REQ_BIAS : state <= WAIT_BIAS;
                WAIT_BIAS : if (param_rd_valid) begin
                    bias <= param_rd_data[((int'(output_row_q[2:0]) << 5)) +: 32];
                    state <= SCALE_PRODUCT;
                end
                SCALE_PRODUCT : state <= SCALE_ROUND;
                SCALE_ROUND : state <= SCALE;
                SCALE : begin
                    overflow <= overflow | scale_ov;
                    if (matrix_desc_q.output_s32) begin
                        pack_buf[(int'(pack_count) << 5) +: 32] <= y32;
                        if (pack_count == 7 || output_row_q + 1 >= matrix_desc_q.n_rows) state <= WRITE;
                        else begin
                            pack_count <= pack_count + 1'b1;
                            output_row_q <= output_row_q + 1'b1;
                            weight_row_addr_q <= weight_row_addr_q + {7'h00, weight_words_per_row};
                            accumulator_q <= 0;
                            state <= REQ_CHUNK;
                        end
                    end else begin
                        pack_buf[(int'(pack_count) << 4) +: 16] <= y16;
                        if (pack_count == 15 || output_row_q + 1 >= matrix_desc_q.n_rows) state <= WRITE;
                        else begin
                            pack_count <= pack_count + 1'b1;
                            output_row_q <= output_row_q + 1'b1;
                            weight_row_addr_q <= weight_row_addr_q + {7'h00, weight_words_per_row};
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
                        weight_row_addr_q <= weight_row_addr_q + {7'h00, weight_words_per_row};
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
