//Ternary Matrix Multiplication
module ternary_mul #(
    parameter int DATA_WIDTH = 16,
    parameter int LANES = 32,
    parameter int MATRIX_ROWS = 512,
    parameter int MATRIX_COLS = 512,
    parameter int DOT_LANES = 32,
    parameter int REDUCE_GROUP = 8,
    parameter int ACC_WIDTH = DATA_WIDTH + $clog2(MATRIX_COLS) + 1,
    parameter bit SATURATE = 1'b0
)(
    input logic clk, rst_n, enable,
    input logic [DATA_WIDTH*LANES-1:0] matrix_in,
    input logic [DATA_WIDTH*LANES-1:0] ternary_matrix,
    output logic [DATA_WIDTH*LANES-1:0] matrix_out,
    output logic tmatmul_write,
    input logic matrix_valid, ternary_valid, output_ready,
    output logic matrix_ready, ternary_ready,
    output logic busy, done, overflow
);
    localparam int WORD_WIDTH = DATA_WIDTH * LANES;
    localparam int VECTOR_WORDS = MATRIX_COLS / LANES;
    localparam int WEIGHT_LANES = WORD_WIDTH / 2;
    localparam int WEIGHT_WORDS = (MATRIX_ROWS*MATRIX_COLS + WEIGHT_LANES-1) / WEIGHT_LANES;
    localparam int WEIGHT_CHUNKS = WEIGHT_LANES / DOT_LANES;
    localparam int ROW_CHUNKS = MATRIX_COLS / DOT_LANES;
    localparam int GROUPS = (DOT_LANES + REDUCE_GROUP-1) / REDUCE_GROUP;
    localparam int MAT_PTR_WIDTH = (VECTOR_WORDS > 1) ? $clog2(VECTOR_WORDS) : 1;
    localparam int WEIGHT_PTR_WIDTH = (WEIGHT_WORDS > 1) ? $clog2(WEIGHT_WORDS) : 1;
    localparam int CHUNK_PTR_WIDTH = (WEIGHT_CHUNKS > 1) ? $clog2(WEIGHT_CHUNKS) : 1;
    localparam int COL_PTR_WIDTH = (ROW_CHUNKS > 1) ? $clog2(ROW_CHUNKS) : 1;
    localparam int ROW_PTR_WIDTH = (MATRIX_ROWS > 1) ? $clog2(MATRIX_ROWS) : 1;
    localparam int LANE_PTR_WIDTH = (LANES > 1) ? $clog2(LANES) : 1;

    // Only the activation vector and one weight word are buffered. No reset
    // on data storage: valid bits prevent stale data after an aborted frame.
    logic [WORD_WIDTH-1:0] matrix_x [VECTOR_WORDS-1:0];
    logic [WORD_WIDTH-1:0] weight_buffer;
    logic [MAT_PTR_WIDTH-1:0] mat_ptr;
    logic [WEIGHT_PTR_WIDTH-1:0] weight_ptr;
    logic [CHUNK_PTR_WIDTH-1:0] weight_chunk;
    logic [COL_PTR_WIDTH-1:0] col_ptr;
    logic [ROW_PTR_WIDTH-1:0] row_ptr;
    logic [LANE_PTR_WIDTH-1:0] lane_ptr;
    logic matrix_loaded, weights_loaded, weight_valid, row_wait;
    logic issue, first_chunk, last_chunk;
    logic read_valid, product_valid, group_valid, reduce_valid, total_valid, result_valid;
    logic [3:0] first_pipe, last_pipe;
    logic [DATA_WIDTH-1:0] activation [DOT_LANES-1:0];
    logic [1:0] weight [DOT_LANES-1:0];
    logic [DATA_WIDTH:0] mul_result [DOT_LANES-1:0];
    logic [ACC_WIDTH-1:0] group_next [GROUPS*2-1:0];
    logic [ACC_WIDTH-1:0] group_result [GROUPS*2-1:0];
    logic [ACC_WIDTH-1:0] reduce_sum_next, reduce_carry_next;
    logic [ACC_WIDTH-1:0] reduce_sum, reduce_carry;
    logic [ACC_WIDTH-1:0] acc_input [3:0];
    logic [ACC_WIDTH-1:0] acc_sum_next, acc_carry_next, acc_sum, acc_carry;
    logic signed [ACC_WIDTH-1:0] row_result;
    logic [WORD_WIDTH-1:0] packed_result;
    logic packed_overflow, row_overflow;
    logic [DATA_WIDTH-1:0] row_output;

    assign matrix_ready = busy && !matrix_loaded;
    assign issue = busy && matrix_loaded && weight_valid && !row_wait && !tmatmul_write;
    assign first_chunk = (col_ptr == 0);
    assign last_chunk = (col_ptr == COL_PTR_WIDTH'(ROW_CHUNKS-1));
    assign ternary_ready = busy && !weights_loaded &&
                           (!weight_valid || (issue && weight_chunk == CHUNK_PTR_WIDTH'(WEIGHT_CHUNKS-1)));

    // Stage 0: registered activation read and weight selection.
    // Stage 1: ternary sign/zero selection. Extend BEFORE negating signed MIN.
    genvar i, j;
    generate
        for (i = 0; i < DOT_LANES; i = i + 1) begin : product_loop
            always_ff @(posedge clk) begin
                if (issue) begin
                    activation[i] <= matrix_x[col_ptr / (LANES/DOT_LANES)]
                        [((col_ptr % (LANES/DOT_LANES))*DOT_LANES+i)*DATA_WIDTH +: DATA_WIDTH];
                    weight[i] <= weight_buffer[i*2 +: 2];
                end
                if (read_valid) begin
                    case (weight[i])
                        2'b01: mul_result[i] <= {activation[i][DATA_WIDTH-1], activation[i]};
                        2'b11: mul_result[i] <= -$signed({activation[i][DATA_WIDTH-1], activation[i]});
                        default: mul_result[i] <= '0; // 00 and reserved 10
                    endcase
                end
            end
        end
        // Stage 2: local reductions, retaining both carry-save words.
        for (i = 0; i < GROUPS; i = i + 1) begin : group_loop
            logic [DATA_WIDTH:0] terms [REDUCE_GROUP-1:0];
            for (j = 0; j < REDUCE_GROUP; j = j + 1) begin : terms_assign
                if (i*REDUCE_GROUP+j < DOT_LANES)
                    assign terms[j] = mul_result[i*REDUCE_GROUP+j];
                else
                    assign terms[j] = '0;
            end
            acc_mul #(.DATA_WIDTH(DATA_WIDTH+1), .NUM_INPUTS(REDUCE_GROUP), .ACC_WIDTH(ACC_WIDTH)) acc_inst (
                .mul_result(terms), .acc_result(),
                .acc_sum(group_next[i*2]), .acc_carry(group_next[i*2+1])
            );
        end
    endgenerate

    // Stage 3: merge the local reductions. No intermediate binary addition.
    acc_mul #(.DATA_WIDTH(ACC_WIDTH), .NUM_INPUTS(GROUPS*2), .ACC_WIDTH(ACC_WIDTH)) reduce_inst (
        .mul_result(group_result), .acc_result(),
        .acc_sum(reduce_sum_next), .acc_carry(reduce_carry_next)
    );

    // Stage 4: two compressor levels in the feedback path.
    assign acc_input[0] = first_pipe[3] ? '0 : acc_sum;
    assign acc_input[1] = first_pipe[3] ? '0 : acc_carry;
    assign acc_input[2] = reduce_sum;
    assign acc_input[3] = reduce_carry;
    acc_mul #(.DATA_WIDTH(ACC_WIDTH), .NUM_INPUTS(4), .ACC_WIDTH(ACC_WIDTH)) accumulate_inst (
        .mul_result(acc_input), .acc_result(),
        .acc_sum(acc_sum_next), .acc_carry(acc_carry_next)
    );

    always_ff @(posedge clk) begin
        if (matrix_valid && matrix_ready)
            matrix_x[mat_ptr] <= matrix_in;
        if (ternary_valid && ternary_ready)
            weight_buffer <= ternary_matrix;
        else if (issue)
            weight_buffer <= weight_buffer >> (DOT_LANES*2);
        if (product_valid) begin
            for (int k = 0; k < GROUPS*2; k = k + 1)
                group_result[k] <= group_next[k];
        end
        if (group_valid) begin
            reduce_sum <= reduce_sum_next;
            reduce_carry <= reduce_carry_next;
        end
        if (reduce_valid) begin
            acc_sum <= acc_sum_next;
            acc_carry <= acc_carry_next;
        end
        // Stage 5: one carry-propagating addition per completed row.
        if (total_valid)
            row_result <= $signed(acc_sum + acc_carry);
    end

    // Stage 6: quantize once, after the complete dot product. Lane 0 is LSB.
    assign row_overflow = row_result[ACC_WIDTH-1:DATA_WIDTH-1] !=
                          {(ACC_WIDTH-DATA_WIDTH+1){row_result[DATA_WIDTH-1]}};
    always_comb begin
        row_output = row_result[DATA_WIDTH-1:0];
        if (SATURATE && row_overflow)
            row_output = row_result[ACC_WIDTH-1] ? {1'b1, {(DATA_WIDTH-1){1'b0}}} :
                                                               {1'b0, {(DATA_WIDTH-1){1'b1}}};
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy <= 1'b0;
            done <= 1'b0;
            tmatmul_write <= 1'b0;
            overflow <= 1'b0;
            matrix_loaded <= 1'b0;
            weights_loaded <= 1'b0;
            weight_valid <= 1'b0;
            row_wait <= 1'b0;
            mat_ptr <= '0;
            weight_ptr <= '0;
            weight_chunk <= '0;
            col_ptr <= '0;
            row_ptr <= '0;
            lane_ptr <= '0;
            read_valid <= 1'b0;
            product_valid <= 1'b0;
            group_valid <= 1'b0;
            reduce_valid <= 1'b0;
            total_valid <= 1'b0;
            result_valid <= 1'b0;
            first_pipe <= '0;
            last_pipe <= '0;
            packed_result <= '0;
            packed_overflow <= 1'b0;
        end
        else begin
            done <= 1'b0;
            read_valid <= issue;
            product_valid <= read_valid;
            group_valid <= product_valid;
            reduce_valid <= group_valid;
            total_valid <= reduce_valid && last_pipe[3];
            result_valid <= total_valid;
            first_pipe <= {first_pipe[2:0], first_chunk};
            last_pipe <= {last_pipe[2:0], last_chunk};
            if (enable && !busy) begin
                busy <= 1'b1;
                matrix_loaded <= 1'b0;
                weights_loaded <= 1'b0;
                weight_valid <= 1'b0;
                mat_ptr <= '0;
                weight_ptr <= '0;
                weight_chunk <= '0;
                col_ptr <= '0;
                row_ptr <= '0;
                lane_ptr <= '0;
                row_wait <= 1'b0;
                packed_result <= '0;
                packed_overflow <= 1'b0;
                overflow <= 1'b0;
            end
            if (matrix_valid && matrix_ready) begin
                if (mat_ptr == MAT_PTR_WIDTH'(VECTOR_WORDS-1))
                    matrix_loaded <= 1'b1;
                else
                    mat_ptr <= mat_ptr + 1'b1;
            end
            if (issue) begin
                if (weight_chunk == CHUNK_PTR_WIDTH'(WEIGHT_CHUNKS-1)) begin
                    weight_chunk <= '0;
                    weight_valid <= 1'b0;
                end
                else
                    weight_chunk <= weight_chunk + 1'b1;
                if (last_chunk) begin
                    col_ptr <= '0;
                    row_wait <= 1'b1;
                end
                else
                    col_ptr <= col_ptr + 1'b1;
            end
            if (ternary_valid && ternary_ready) begin
                weight_valid <= 1'b1;
                if (weight_ptr == WEIGHT_PTR_WIDTH'(WEIGHT_WORDS-1))
                    weights_loaded <= 1'b1;
                else
                    weight_ptr <= weight_ptr + 1'b1;
            end
            if (result_valid) begin
                packed_result[lane_ptr*DATA_WIDTH +: DATA_WIDTH] <= row_output;
                packed_overflow <= packed_overflow | row_overflow;
                if (lane_ptr == LANE_PTR_WIDTH'(LANES-1) || row_ptr == ROW_PTR_WIDTH'(MATRIX_ROWS-1)) begin
                    tmatmul_write <= 1'b1;
                    overflow <= packed_overflow | row_overflow;
                end
                else begin
                    lane_ptr <= lane_ptr + 1'b1;
                    row_ptr <= row_ptr + 1'b1;
                    row_wait <= 1'b0;
                end
            end
            if (tmatmul_write && output_ready) begin
                tmatmul_write <= 1'b0;
                packed_result <= '0;
                packed_overflow <= 1'b0;
                overflow <= 1'b0;
                lane_ptr <= '0;
                if (row_ptr == ROW_PTR_WIDTH'(MATRIX_ROWS-1)) begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    weight_valid <= 1'b0;
                end
                else begin
                    row_ptr <= row_ptr + 1'b1;
                    row_wait <= 1'b0;
                end
            end
        end
    end
    assign matrix_out = packed_result;

    // synthesis translate_off
    initial begin
        if (DATA_WIDTH < 1 || LANES < 1 || MATRIX_ROWS < 1 || MATRIX_COLS < 1 ||
            DOT_LANES < 1 || DOT_LANES > LANES || REDUCE_GROUP < 1 ||
            MATRIX_COLS % LANES != 0 || LANES % DOT_LANES != 0 ||
            WORD_WIDTH % 2 != 0 || WEIGHT_LANES % DOT_LANES != 0 ||
            ACC_WIDTH < DATA_WIDTH + $clog2(MATRIX_COLS) + 1)
            $fatal(1, "Invalid ternary matrix parameters");
    end
    // synthesis translate_on
endmodule
