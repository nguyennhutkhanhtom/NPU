module rowwise_op (
    input logic clk, rst_n, start,
    input logic [3:0] select,
    input logic [255:0] a_word, b_word, c_word,
    input logic [4:0] a_frac_bits, b_frac_bits, dst_frac_bits, valid_elems,
    input logic a_unsigned, b_unsigned, dst_unsigned,
    output logic [255:0] result_word,
    output logic busy, done, overflow, format_error
);
    import npu_pkg::*;
    localparam logic [3:0] OP_ADD = 4'h1;
    localparam logic [3:0] OP_SUB = 4'h2;
    localparam logic [3:0] OP_MUL = 4'h3;
    localparam logic [3:0] OP_SIG = 4'h6;
    localparam logic [3:0] OP_REC = 4'hb;
    localparam logic [3:0] OP_RELU = 4'hc;
    typedef enum logic [2:0] {IDLE, LOAD, MULTIPLY, RAW, ROUND, PACK, SIG_WAIT} state_t;
    state_t state;

    logic [255:0] source_a_q, source_b_q, state_word_q;
    logic [255:0] result_buffer_q, result_buffer_next;
    logic [4:0] source_a_frac_q, element_count_q, element_index_q;
    logic source_a_unsigned_q, source_b_unsigned_q, destination_unsigned_q;
    logic [3:0] operation_q;
    logic signed [6:0] result_shift_q;

    logic sig_busy, sig_done, sig_start;
    logic [15:0] sig_y;
    logic signed [15:0] sig_x_q;
    assign sig_start = busy && state == SIG_WAIT && !sig_busy && !sig_done;
    sigmoid u_sig(
        .clk(clk),
        .rst_n(rst_n),
        .start(sig_start),
        .x_raw(sig_x_q),
        .frac_bits(source_a_frac_q),
        .busy(sig_busy),
        .done(sig_done),
        .y_raw(sig_y));

    logic signed [16:0] lane_a[0:1], lane_b[0:1];
    logic signed [16:0] lane_a_q[0:1], lane_b_q[0:1];
    logic signed [16:0] multiply_a[0:1], multiply_b[0:1];
    logic [15:0] magnitude_a[0:1], magnitude_b[0:1];
    logic [15:0] magnitude_a_q[0:1], magnitude_b_q[0:1];
    // MUL and REC retain two unsigned 16x16 multipliers. Their inputs and
    // outputs have registers, so lane selection and sign correction are
    // separate from multiplication. Arithmetic payloads need no reset.
    logic [31:0] magnitude_product_q[0:1];
    logic [1:0] product_negative_q, lane_valid_q;
    logic signed [31:0] product[0:1];
    logic signed [32:0] recurrent_sum;
    logic signed [32:0] raw_value_q[0:1];
    logic signed [63:0] scaled_q[0:1];
    logic signed [15:0] old_state, candidate;
    logic [15:0] gate, complement;
    logic source_format_error, source_format_error_q;
    logic lane_overflow, lane_format_error;

    always_comb begin
        candidate = source_a_q[element_index_q * 16 +: 16];
        old_state = state_word_q[element_index_q * 16 +: 16];
        gate = source_b_q[element_index_q * 16 +: 16];
        complement = 16'h8000 - gate;
        source_format_error = 1'b0;
        for (integer j = 0; j < 2; j = j + 1) begin
            lane_a[j] = source_a_unsigned_q ? $signed({1'b0, source_a_q[(element_index_q + j) * 16 +: 16]}) : $signed(source_a_q[(element_index_q + j) * 16 +: 16]);
            lane_b[j] = source_b_unsigned_q ? $signed({1'b0, source_b_q[(element_index_q + j) * 16 +: 16]}) : $signed(source_b_q[(element_index_q + j) * 16 +: 16]);
            multiply_a[j] = '0;
            multiply_b[j] = '0;
            if (operation_q == OP_MUL && element_index_q + j < element_count_q) begin
                multiply_a[j] = lane_a[j];
                multiply_b[j] = lane_b[j];
            end else if (operation_q == OP_REC) begin
                multiply_a[j] = (j == 0) ? {old_state[15], old_state} : {candidate[15], candidate};
                multiply_b[j] = (j == 0) ? $signed({1'b0, gate}) : $signed({1'b0, complement});
            end
            magnitude_a[j] = 16'(multiply_a[j][16] ? - multiply_a[j] : multiply_a[j]);
            magnitude_b[j] = 16'(multiply_b[j][16] ? - multiply_b[j] : multiply_b[j]);
            if (element_index_q + j < element_count_q && operation_q != OP_RELU &&
                ((source_a_unsigned_q && lane_a[j] > 17'sh0_8000) ||
                (source_b_unsigned_q && lane_b[j] > 17'sh0_8000))) source_format_error = 1'b1;
            product[j] = product_negative_q[j] ?
                - $signed(magnitude_product_q[j]) : $signed(magnitude_product_q[j]);
        end
        if (operation_q == OP_REC) source_format_error = gate > 16'h8000;
        recurrent_sum = {product[0][31], product[0]} + {product[1][31], product[1]};
    end

    // Each enable is the validity of its payload. Reset only cancels the FSM;
    // uninitialized arithmetic registers cannot reach architectural outputs.
    always_ff @(posedge clk) begin
        if (rst_n && start && !busy) begin
            source_a_q <= a_word;
            source_b_q <= b_word;
            state_word_q <= c_word;
        end
        if (rst_n && busy) begin
            case (state)
                LOAD : begin
                    sig_x_q <= source_a_q[element_index_q * 16 +: 16];
                    source_format_error_q <= source_format_error;
                    for (integer j = 0; j < 2; j = j + 1) begin
                        lane_a_q[j] <= lane_a[j];
                        lane_b_q[j] <= lane_b[j];
                        magnitude_a_q[j] <= magnitude_a[j];
                        magnitude_b_q[j] <= magnitude_b[j];
                        product_negative_q[j] <= multiply_a[j][16] ^ multiply_b[j][16];
                        lane_valid_q[j] <= element_index_q + j < element_count_q;
                    end
                end
                MULTIPLY : for (integer j = 0; j < 2; j = j + 1)
                    magnitude_product_q[j] <= magnitude_a_q[j] * magnitude_b_q[j];
                RAW : for (integer j = 0; j < 2; j = j + 1) begin
                    case (operation_q)
                        OP_ADD : raw_value_q[j] <= 33'(lane_a_q[j]) + 33'(lane_b_q[j]);
                        OP_SUB : raw_value_q[j] <= 33'(lane_a_q[j]) - 33'(lane_b_q[j]);
                        OP_RELU : raw_value_q[j] <= lane_a_q[j] < 0 ? 33'sh0 : 33'(lane_a_q[j]);
                        OP_REC : raw_value_q[j] <= (j == 0) ? recurrent_sum : 33'sh0;
                        default : raw_value_q[j] <= {product[j][31], product[j]};
                    endcase
                end
                ROUND : for (integer j = 0; j < 2; j = j + 1)
                    scaled_q[j] <= scale_shift64({{31{raw_value_q[j][32]}}, raw_value_q[j]}, int'(result_shift_q));
                default : ;
            endcase
        end
    end

    always_comb begin
        result_buffer_next = result_buffer_q;
        lane_overflow = 1'b0;
        lane_format_error = source_format_error_q;
        for (integer j = 0; j < 2; j = j + 1) begin
            if (lane_valid_q[j]) begin
                if (destination_unsigned_q && operation_q != OP_RELU) begin
                    if (scaled_q[j] < 0) begin
                        result_buffer_next[(element_index_q + j) * 16 +: 16] = 0;
                        lane_overflow = 1'b1;
                    end else if (scaled_q[j] > 64'sh0000_0000_0000_8000) begin
                        result_buffer_next[(element_index_q + j) * 16 +: 16] = 16'h8000;
                        lane_overflow = 1'b1;
                    end else result_buffer_next[(element_index_q + j) * 16 +: 16] = scaled_q[j][15:0];
                end else begin
                    result_buffer_next[(element_index_q + j) * 16 +: 16] = sat_s16(scaled_q[j]);
                    if (scaled_q[j] > 64'sh0000_0000_0000_7fff || scaled_q[j] < - 64'sh0000_0000_0000_8000) lane_overflow = 1'b1;
                end
            end
        end
        if (operation_q == OP_SIG) begin
            result_buffer_next = result_buffer_q;
            result_buffer_next[element_index_q * 16 +: 16] = sig_y;
        end
        if (operation_q == OP_REC) begin
            result_buffer_next = result_buffer_q;
            result_buffer_next[element_index_q * 16 +: 16] = sat_s16(scaled_q[0]);
            lane_overflow = scaled_q[0] > 64'sh0000_0000_0000_7fff || scaled_q[0] < - 64'sh0000_0000_0000_8000;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            busy <= 0;
            done <= 0;
            overflow <= 0;
            format_error <= 0;
            result_word <= 0;
            result_buffer_q <= 0;
            source_a_frac_q <= 0;
            source_a_unsigned_q <= 0;
            source_b_unsigned_q <= 0;
            destination_unsigned_q <= 0;
            element_count_q <= 0;
            element_index_q <= 0;
            operation_q <= 0;
            result_shift_q <= 0;
        end else begin
            done <= 0;
            if (start && !busy) begin
                source_a_frac_q <= a_frac_bits;
                source_a_unsigned_q <= a_unsigned;
                source_b_unsigned_q <= b_unsigned;
                destination_unsigned_q <= dst_unsigned;
                element_count_q <= valid_elems;
                operation_q <= select;
                result_shift_q <= 7'(select == OP_REC ? 15 :
                    (select == OP_MUL ? int'(a_frac_bits) + int'(b_frac_bits) : int'(a_frac_bits)) - int'(dst_frac_bits));
                element_index_q <= 0;
                result_buffer_q <= 0;
                busy <= 1;
                overflow <= 0;
                format_error <= 0;
                state <= LOAD;
                if (valid_elems == 0 || valid_elems > 16 || a_frac_bits > 24 || b_frac_bits > 24 || dst_frac_bits > 24 ||
                    !(select == OP_ADD || select == OP_SUB || select == OP_MUL || select == OP_SIG || select == OP_REC || select == OP_RELU)) begin
                    busy <= 0;
                    done <= 1;
                    format_error <= 1;
                    result_word <= 0;
                    state <= IDLE;
                end
            end else if (busy) begin
                case (state)
                    LOAD : state <= operation_q == OP_SIG ? SIG_WAIT : MULTIPLY;
                    MULTIPLY : state <= RAW;
                    RAW : state <= ROUND;
                    ROUND : state <= PACK;
                    SIG_WAIT : if (sig_done) begin
                        result_buffer_q <= result_buffer_next;
                        if (element_index_q + 1 >= element_count_q) begin
                            result_word <= result_buffer_next;
                            busy <= 0;
                            done <= 1;
                            state <= IDLE;
                        end else begin
                            element_index_q <= element_index_q + 1'b1;
                            state <= LOAD;
                        end
                    end
                    PACK : begin
                        result_buffer_q <= result_buffer_next;
                        overflow <= overflow | lane_overflow;
                        format_error <= format_error | lane_format_error;
                        if (element_index_q + (operation_q == OP_REC ? 1 : 2) >= element_count_q || lane_format_error) begin
                            result_word <= result_buffer_next;
                            busy <= 0;
                            done <= 1;
                            state <= IDLE;
                        end else begin
                            element_index_q <= element_index_q + (operation_q == OP_REC ? 5'd1 : 5'd2);
                            state <= LOAD;
                        end
                    end
                    default : state <= IDLE;
                endcase
            end
        end
    end
endmodule
