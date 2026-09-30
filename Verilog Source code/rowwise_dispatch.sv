module rowwise_dispatch #(parameter string SIG_LUT_FILE = "") (
    input logic clk, rst_n, start,
    input logic [3:0] op,
    input npu_pkg::ws_desc_t a_desc, b_desc, dst_desc,
    output logic ws_rd_en,
    output logic [7:0] ws_rd_addr,
    input logic [255:0] ws_rd_data,
    input logic ws_rd_valid,
    output logic ws_wr_en,
    output logic [7:0] ws_wr_addr,
    output logic [255:0] ws_wr_data,
    output logic busy, done, overflow, format_error
);
    import npu_pkg::*;
    typedef enum logic [3:0] {IDLE, REQ_A, WAIT_A, REQ_B, WAIT_B, START_ALU, WAIT_ALU, WRITE, FINISH, REQ_C, WAIT_C} state_t;
    state_t state;
    ws_desc_t source_a_desc_q, source_b_desc_q, destination_desc_q;
    logic [3:0] operation_q;
    logic [7:0] word_index_q, word_count_q;
    logic [255:0] a_word, b_word, c_word, alu_result;
    logic alu_busy, alu_done, alu_ov, alu_error, invalid;
    logic [4:0] valid_elems;
    always_comb begin
        invalid = !ws_valid(a_desc) || !ws_valid(dst_desc) || a_desc.length != dst_desc.length;
        if (op == 6) begin
            invalid = invalid || a_desc.fmt != FMT_S16 || dst_desc.fmt != FMT_U16 || dst_desc.frac_bits != 15;
        end else if (op == 12) begin
            invalid = invalid || a_desc.fmt != FMT_S16 || dst_desc.fmt != FMT_S16;
        end else begin
            invalid = invalid || !ws_valid(b_desc) || a_desc.length != b_desc.length;
            case (op)
                1, 2 : invalid = invalid || a_desc.frac_bits != b_desc.frac_bits ||
                a_desc.fmt != b_desc.fmt || dst_desc.fmt != a_desc.fmt ||
                !(a_desc.fmt == FMT_S16 || a_desc.fmt == FMT_U16);
                3 : invalid = invalid || a_desc.fmt != FMT_S16 || dst_desc.fmt != FMT_S16 ||
                !(b_desc.fmt == FMT_S16 || b_desc.fmt == FMT_U16);
                11 : invalid = invalid || a_desc.fmt != FMT_S16 || dst_desc.fmt != FMT_S16 ||
                a_desc.frac_bits != dst_desc.frac_bits || b_desc.fmt != FMT_U16 || b_desc.frac_bits != 15 ||
                ranges_overlap(int'(b_desc.base_word), ws_words(b_desc), int'(dst_desc.base_word), ws_words(dst_desc));
                default : invalid = 1;
            endcase
            if (b_desc.fmt == FMT_U16 && b_desc.frac_bits != 15) invalid = 1;
            if (b_desc.base_word != dst_desc.base_word &&
                ranges_overlap(int'(b_desc.base_word), ws_words(b_desc), int'(dst_desc.base_word), ws_words(dst_desc))) invalid = 1;
        end
        if (a_desc.fmt == FMT_U16 && a_desc.frac_bits != 15) invalid = 1;
        if (dst_desc.fmt == FMT_U16 && dst_desc.frac_bits != 15) invalid = 1;
        if (a_desc.base_word != dst_desc.base_word &&
            ranges_overlap(int'(a_desc.base_word), ws_words(a_desc), int'(dst_desc.base_word), ws_words(dst_desc))) invalid = 1;
        valid_elems = (int'(source_a_desc_q.length) - int'(word_index_q) * 16 >= 16) ? 5'd16 : 5'(int'(source_a_desc_q.length) - int'(word_index_q) * 16);
    end
    rowwise_op #(.SIG_LUT_FILE(SIG_LUT_FILE)) u_alu(
        .clk(clk),
        .rst_n(rst_n),
        .start(state == START_ALU),
        .select(operation_q),
        .a_word(a_word),
        .b_word(b_word),
        .c_word(c_word),
        .a_frac_bits(source_a_desc_q.frac_bits),
        .b_frac_bits(source_b_desc_q.frac_bits),
        .dst_frac_bits(destination_desc_q.frac_bits),
        .valid_elems(valid_elems),
        .a_unsigned(source_a_desc_q.fmt == FMT_U16),
        .b_unsigned(source_b_desc_q.fmt == FMT_U16),
        .dst_unsigned(destination_desc_q.fmt == FMT_U16),
        .result_word(alu_result),
        .busy(alu_busy),
        .done(alu_done),
        .overflow(alu_ov),
        .format_error(alu_error));
    always_comb begin
        ws_rd_en = 0;
        ws_rd_addr = 0;
        ws_wr_en = 0;
        ws_wr_addr = destination_desc_q.base_word + word_index_q;
        ws_wr_data = alu_result;
        case (state)
            REQ_A : begin
                ws_rd_en = 1;
                ws_rd_addr = source_a_desc_q.base_word + word_index_q;
            end
            REQ_B : begin
                ws_rd_en = 1;
                ws_rd_addr = source_b_desc_q.base_word + word_index_q;
            end
            REQ_C : begin
                ws_rd_en = 1;
                ws_rd_addr = destination_desc_q.base_word + word_index_q;
            end
            WRITE : ws_wr_en = 1;
            default : ;
        endcase
    end
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            busy <= 0;
            done <= 0;
            overflow <= 0;
            format_error <= 0;
            source_a_desc_q <= '0;
            source_b_desc_q <= '0;
            destination_desc_q <= '0;
            operation_q <= 0;
            word_index_q <= 0;
            word_count_q <= 0;
            a_word <= 0;
            b_word <= 0;
            c_word <= 0;
        end else begin
            done <= 0;
            case (state)
                IDLE : if (start) begin
                    source_a_desc_q <= a_desc;
                    source_b_desc_q <= b_desc;
                    destination_desc_q <= dst_desc;
                    operation_q <= op;
                    word_index_q <= 0;
                    word_count_q <= 8'((int'(a_desc.length) + 15) / 16);
                    busy <= 1;
                    overflow <= 0;
                    format_error <= invalid;
                    if (invalid) state <= FINISH;
                    else state <= REQ_A;
                end
                REQ_A : state <= WAIT_A;
                WAIT_A : if (ws_rd_valid) begin
                    a_word <= ws_rd_data;
                    if (operation_q == 6 || operation_q == 12) begin
                        source_b_desc_q <= '0;
                        b_word <= 0;
                        state <= START_ALU;
                    end else state <= REQ_B;
                end
                REQ_B : state <= WAIT_B;
                WAIT_B : if (ws_rd_valid) begin
                    b_word <= ws_rd_data;
                    state <= (operation_q == 11) ? REQ_C : START_ALU;
                end
                REQ_C : state <= WAIT_C;
                WAIT_C : if (ws_rd_valid) begin
                    c_word <= ws_rd_data;
                    state <= START_ALU;
                end
                START_ALU : state <= WAIT_ALU;
                WAIT_ALU : if (alu_done) begin
                    overflow <= overflow | alu_ov;
                    format_error <= format_error | alu_error;
                    state <= alu_error ? FINISH : WRITE;
                end
                WRITE : if (word_index_q + 1 >= word_count_q) state <= FINISH;
                else begin
                    word_index_q <= word_index_q + 1'b1;
                    state <= REQ_A;
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
