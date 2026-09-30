module rowwise_op #(parameter string SIG_LUT_FILE = "") (
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
    logic [255:0] source_a_q, source_b_q, state_word_q, result_buffer_q, result_buffer_next;
    logic [4:0] source_a_frac_q, source_b_frac_q, destination_frac_q, element_count_q, element_index_q;
    logic source_a_unsigned_q, source_b_unsigned_q, destination_unsigned_q;
    logic [3:0] operation_q;
    logic sig_busy, sig_done, sig_start;
    logic [15:0] sig_y;
    logic signed [15:0] sig_x;
    assign sig_x = source_a_q[element_index_q * 16 +: 16];
    assign sig_start = busy && operation_q == OP_SIG && !sig_busy && !sig_done;
    sigmoid #(.LUT_FILE(SIG_LUT_FILE)) u_sig(
        .clk(clk),
        .rst_n(rst_n),
        .start(sig_start),
        .x_raw(sig_x),
        .frac_bits(source_a_frac_q),
        .busy(sig_busy),
        .done(sig_done),
        .y_raw(sig_y));
    logic lane_overflow, lane_format_error;
    logic signed [16:0] lane_a[0:1], lane_b[0:1];
    // MUL and REC share these two physical unsigned 16x16 multipliers.
    // Sign correction happens after multiplication, preserving gate raw 0x8000.
    logic signed [16:0] multiply_a[0:1], multiply_b[0:1];
    logic [15:0] magnitude_a[0:1], magnitude_b[0:1];
    logic [31:0] magnitude_product[0:1];
    logic signed [31:0] product[0:1];
    logic signed [63:0] raw_value[0:1], scaled[0:1];
    logic signed [15:0] old_state, candidate;
    logic [15:0] gate, complement;
    logic signed [32:0] recurrent_sum;
    logic signed [63:0] recurrent_value;
    integer result_shift;
    always_comb begin
        result_buffer_next = result_buffer_q;
        lane_overflow = 0;
        lane_format_error = 0;
        candidate = source_a_q[element_index_q * 16 +: 16];
        old_state = state_word_q[element_index_q * 16 +: 16];
        gate = source_b_q[element_index_q * 16 +: 16];
        complement = 16'h8000 - gate;
        result_shift = (operation_q == OP_MUL ? int'(source_a_frac_q) + int'(source_b_frac_q) : int'(source_a_frac_q)) - int'(destination_frac_q);
        for (integer j = 0;j < 2;j = j + 1) begin
            lane_a[j] = source_a_unsigned_q ? $signed({1'b0, source_a_q[(element_index_q + j) * 16 +: 16]}) : $signed(source_a_q[(element_index_q + j) * 16 +: 16]);
            lane_b[j] = source_b_unsigned_q ? $signed({1'b0, source_b_q[(element_index_q + j) * 16 +: 16]}) : $signed(source_b_q[(element_index_q + j) * 16 +: 16]);
            // Operand isolation avoids toggling multipliers during ADD/SIG/idle.
            multiply_a[j] = '0;
            multiply_b[j] = '0;
            if (busy && operation_q == OP_MUL && element_index_q + j < element_count_q) begin
                multiply_a[j] = lane_a[j];
                multiply_b[j] = lane_b[j];
            end else if (busy && operation_q == OP_REC) begin
                multiply_a[j] = (j == 0) ? {old_state[15], old_state} : {candidate[15], candidate};
                multiply_b[j] = (j == 0) ? $signed({1'b0, gate}) : $signed({1'b0, complement});
            end
            // The magnitude of an S16 or valid U16/F15 operand fits in 16 bits.
            magnitude_a[j] = 16'(multiply_a[j][16] ? - multiply_a[j] : multiply_a[j]);
            magnitude_b[j] = 16'(multiply_b[j][16] ? - multiply_b[j] : multiply_b[j]);
            magnitude_product[j] = magnitude_a[j] * magnitude_b[j];
            product[j] = (multiply_a[j][16] ^ multiply_b[j][16]) ?
             - $signed(magnitude_product[j]) : $signed(magnitude_product[j]);
            case (operation_q)
                OP_ADD : raw_value[j] = 64'(lane_a[j]) + 64'(lane_b[j]);
                OP_SUB : raw_value[j] = 64'(lane_a[j]) - 64'(lane_b[j]);
                default : raw_value[j] = {{32{product[j][31]}}, product[j]};
            endcase
            scaled[j] = scale_shift64(raw_value[j], result_shift);
            if (element_index_q + j < element_count_q) begin
                if ((source_a_unsigned_q && lane_a[j] > 17'sh0_8000) || (source_b_unsigned_q && lane_b[j] > 17'sh0_8000)) lane_format_error = 1;
                if (destination_unsigned_q) begin
                    if (scaled[j] < 0) begin
                        result_buffer_next[(element_index_q + j) * 16 +: 16] = 0;
                        lane_overflow = 1;
                    end
                    else if (scaled[j] > 64'sh0000_0000_0000_8000) begin
                        result_buffer_next[(element_index_q + j) * 16 +: 16] = 16'h8000;
                        lane_overflow = 1;
                    end
                    else result_buffer_next[(element_index_q + j) * 16 +: 16] = scaled[j][15:0];
                end else begin
                    result_buffer_next[(element_index_q + j) * 16 +: 16] = sat_s16(scaled[j]);
                    if (scaled[j] > 64'sh0000_0000_0000_7fff || scaled[j] < - 64'sh0000_0000_0000_8000) lane_overflow = 1;
                end
            end
        end
        if (operation_q == OP_SIG) begin
            result_buffer_next = result_buffer_q;
            result_buffer_next[element_index_q * 16 +: 16] = sig_y;
        end
        if (operation_q == OP_RELU) begin
            result_buffer_next = result_buffer_q;
            lane_overflow = 0;
            lane_format_error = 0;
            for (integer j = 0;j < 2;j = j + 1) if (element_index_q + j < element_count_q) begin
                scaled[j] = scale_shift64(lane_a[j] < 0 ? 64'sh0000_0000_0000_0000 : 64'(lane_a[j]), int'(source_a_frac_q) - int'(destination_frac_q));
                result_buffer_next[(element_index_q + j) * 16 +: 16] = sat_s16(scaled[j]);
                if (scaled[j] > 64'sh0000_0000_0000_7fff) lane_overflow = 1;
            end
        end
        recurrent_sum = {product[0][31], product[0]} + {product[1][31], product[1]};
        recurrent_value = rne_shift64({{31{recurrent_sum[32]}}, recurrent_sum}, 6'd15);
        if (operation_q == OP_REC) begin
            result_buffer_next = result_buffer_q;
            result_buffer_next[element_index_q * 16 +: 16] = sat_s16(recurrent_value);
            lane_format_error = gate > 16'h8000;
            lane_overflow = (recurrent_value > 64'sh0000_0000_0000_7fff || recurrent_value < - 64'sh0000_0000_0000_8000);
        end
    end
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy <= 0;
            done <= 0;
            overflow <= 0;
            format_error <= 0;
            result_word <= 0;
            source_a_q <= 0;
            source_b_q <= 0;
            state_word_q <= 0;
            result_buffer_q <= 0;
            source_a_frac_q <= 0;
            source_b_frac_q <= 0;
            destination_frac_q <= 0;
            element_count_q <= 0;
            element_index_q <= 0;
            source_a_unsigned_q <= 0;
            source_b_unsigned_q <= 0;
            destination_unsigned_q <= 0;
            operation_q <= 0;
        end else begin
            done <= 0;
            if (start && !busy) begin
                source_a_q <= a_word;
                source_b_q <= b_word;
                state_word_q <= c_word;
                source_a_frac_q <= a_frac_bits;
                source_b_frac_q <= b_frac_bits;
                destination_frac_q <= dst_frac_bits;
                source_a_unsigned_q <= a_unsigned;
                source_b_unsigned_q <= b_unsigned;
                destination_unsigned_q <= dst_unsigned;
                element_count_q <= valid_elems;
                operation_q <= select;
                element_index_q <= 0;
                result_buffer_q <= 0;
                busy <= 1;
                overflow <= 0;
                format_error <= 0;
                if (valid_elems == 0 || valid_elems > 16 || a_frac_bits > 24 || b_frac_bits > 24 || dst_frac_bits > 24 ||
                    !(select == OP_ADD || select == OP_SUB || select == OP_MUL || select == OP_SIG || select == OP_REC || select == OP_RELU)) begin
                    busy <= 0;
                    done <= 1;
                    format_error <= 1;
                    result_word <= 0;
                end
            end else if (busy) begin
                if (operation_q == OP_SIG) begin
                    if (sig_done) begin
                        result_buffer_q <= result_buffer_next;
                        if (element_index_q + 1 >= element_count_q) begin
                            result_word <= result_buffer_next;
                            busy <= 0;
                            done <= 1;
                        end
                        else element_index_q <= element_index_q + 1'b1;
                    end
                end else begin
                    result_buffer_q <= result_buffer_next;
                    overflow <= overflow | lane_overflow;
                    format_error <= format_error | lane_format_error;
                    if (element_index_q + (operation_q == OP_REC ? 1 : 2) >= element_count_q || lane_format_error) begin
                        result_word <= result_buffer_next;
                        busy <= 0;
                        done <= 1;
                    end
                    else element_index_q <= element_index_q + (operation_q == OP_REC ? 5'd1 : 5'd2);
                end
            end
        end
    end
endmodule
