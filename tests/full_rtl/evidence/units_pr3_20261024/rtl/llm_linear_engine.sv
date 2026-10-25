// Ordered row stream. Two parameter-word credits and four reserved result
// slots bound overlap with the parent epilogue. Dot sums retire in issue order.
module llm_linear_engine (
    input logic clk, rst_n, start_i, cancel_i,
    input logic [14:0] weight_base_i,
    input logic [3:0] chunks_i,
    input logic [9:0] rows_i,
    input logic result_ready_i,
    output logic result_valid_o, result_fault_o,
    output logic ready_o, busy_o, done_o, fault_o,
    output logic parameter_req_o,
    output logic [14:0] parameter_address_o,
    input logic parameter_valid_i,
    input logic [255:0] parameter_data_i,
    output logic [3:0] input_chunk_o,
    input logic signed [23:0] x_i [0:31],
    output logic dot_issue_o,
    output logic signed [38:0] accumulator_o
);
    genvar lane;
    typedef enum logic [1:0] {IDLE, RUN, DRAIN} state_t;
    state_t state;
    logic [14:0] base_q;
    logic [3:0] chunks_q, input_chunk_q, retire_chunk_q;
    logic [9:0] rows_q, issue_row_q, started_rows_q, consumed_rows_q;
    logic [13:0] issue_q, retired_q;
    logic [11:0] request_q, response_q, words_consumed, words_required;
    logic [1:0] fifo_valid_q;
    logic [255:0] fifo_q [0:1];
    logic launch_q;
    logic signed [23:0] x_q [0:31];
    logic [1:0] w_q [0:31];
    wire dot_valid, dot_reserved;
    wire signed [29:0] dot_sum;
    logic signed [38:0] accumulator_q;
    logic signed [38:0] result_q [0:3];
    logic [3:0] result_fault_q;
    logic [1:0] result_read_q, result_write_q;
    logic [2:0] result_count_q;
    wire result_pop = result_valid_o && result_ready_i;
    wire row_last = retire_chunk_q + 1'b1 == chunks_q;
    wire result_push = state == RUN && !cancel_i && dot_valid && (row_last || dot_reserved);
    wire row_credit = input_chunk_q != 0 || (started_rows_q - consumed_rows_q) < 10'd4;
    wire operand_capture = state == RUN && !cancel_i && !(dot_valid && dot_reserved) &&
        issue_row_q < rows_q && row_credit && fifo_valid_q[words_consumed[0]];
    assign ready_o = rst_n && state == IDLE && result_count_q == 0;
    assign busy_o = state != IDLE || result_count_q != 0;
    assign result_valid_o = rst_n && !cancel_i && result_count_q != 0;
    assign result_fault_o = result_fault_q[result_read_q];
    assign accumulator_o = result_q[result_read_q];
    assign parameter_req_o = state == RUN && !cancel_i && !(dot_valid && dot_reserved) &&
        request_q < words_required && (request_q - words_consumed) < 12'd2;
    assign parameter_address_o = base_q + 15'(request_q);
    assign input_chunk_o = input_chunk_q;
    assign dot_issue_o = launch_q;
    ternary_dot32 u_dot(.clk(clk), .rst_n(rst_n), .valid_i(launch_q),
        .x_i(x_q), .w_i(w_q), .valid_o(dot_valid), .reserved_o(dot_reserved), .sum_o(dot_sum));
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE; done_o <= 0; fault_o <= 0; launch_q <= 0;
            issue_q <= 0; retired_q <= 0; request_q <= 0; response_q <= 0; fifo_valid_q <= 0;
            words_consumed <= 0; input_chunk_q <= 0; retire_chunk_q <= 0; issue_row_q <= 0;
            started_rows_q <= 0; consumed_rows_q <= 0;
            result_count_q <= 0; result_read_q <= 0; result_write_q <= 0;
        end else begin
            done_o <= 0;
            launch_q <= operand_capture;
            if (ready_o && start_i && !cancel_i) begin
                state <= RUN; issue_q <= 0; retired_q <= 0; request_q <= 0; response_q <= 0;
                fifo_valid_q <= 0; fault_o <= 0;
                words_consumed <= 0; input_chunk_q <= 0; retire_chunk_q <= 0; issue_row_q <= 0;
                started_rows_q <= 0; consumed_rows_q <= 0;
                result_count_q <= 0; result_read_q <= 0; result_write_q <= 0;
            end else begin
                if (cancel_i) begin
                    result_count_q <= 0; result_read_q <= 0; result_write_q <= 0;
                end else begin
                    case ({result_push, result_pop})
                        2'b10: result_count_q <= result_count_q + 1'b1;
                        2'b01: result_count_q <= result_count_q - 1'b1;
                        default: ;
                    endcase
                    if (result_push) result_write_q <= result_write_q + 1'b1;
                    if (result_pop) begin
                        result_read_q <= result_read_q + 1'b1;
                        consumed_rows_q <= consumed_rows_q + 1'b1;
                    end
                end
                if (state != IDLE) begin
                if (parameter_req_o) request_q <= request_q + 1'b1;
                if (parameter_valid_i && response_q < request_q) begin
                    response_q <= response_q + 1'b1;
                    fifo_valid_q[response_q[0]] <= 1;
                end
                if (operand_capture) begin
                    issue_q <= issue_q + 1'b1;
                    if (input_chunk_q == 0) started_rows_q <= started_rows_q + 1'b1;
                    if (input_chunk_q[1:0] == 3) begin
                        fifo_valid_q[words_consumed[0]] <= 0;
                        words_consumed <= words_consumed + 1'b1;
                    end
                    if (input_chunk_q + 1'b1 == chunks_q) begin
                        input_chunk_q <= 0; issue_row_q <= issue_row_q + 1'b1;
                    end else input_chunk_q <= input_chunk_q + 1'b1;
                end
                if (dot_valid) begin
                    retired_q <= retired_q + 1'b1;
                    if (state == RUN) begin
                        if (row_last) retire_chunk_q <= 0;
                        else retire_chunk_q <= retire_chunk_q + 1'b1;
                        if (dot_reserved) begin state <= DRAIN; fault_o <= 1; end
                        else if (row_last && issue_row_q == rows_q && retired_q + 1'b1 == issue_q)
                            state <= DRAIN;
                    end
                end
                if (cancel_i && state == RUN) begin state <= DRAIN; fault_o <= 1; end
                else if (state == DRAIN && response_q == request_q && retired_q == issue_q && !launch_q) begin
                    state <= IDLE; done_o <= 1; fifo_valid_q <= 0;
                end
                end
            end
        end
    end
    always_ff @(posedge clk)
        if (rst_n) begin
            if (ready_o && start_i && !cancel_i) begin
                base_q <= weight_base_i; chunks_q <= chunks_i; rows_q <= rows_i;
                // Validated geometry is four or twelve chunks per row.
                words_required <= chunks_i == 12 ? (12'(rows_i) << 1) + 12'(rows_i) : 12'(rows_i);
                accumulator_q <= 0;
            end else if (state == RUN && dot_valid && !dot_reserved && !cancel_i) begin
                if (row_last) accumulator_q <= 0;
                else accumulator_q <= accumulator_q + 39'(dot_sum);
            end
            if (result_push) begin
                result_q[result_write_q] <= accumulator_q + 39'(dot_sum);
                result_fault_q[result_write_q] <= dot_reserved;
            end
            if (state != IDLE && parameter_valid_i && response_q < request_q)
                fifo_q[response_q[0]] <= parameter_data_i;
        end
    generate
    for (lane = 0; lane < 32; lane = lane + 1) begin : g_operand
        always_ff @(posedge clk)
            if (rst_n && operand_capture) begin
                x_q[lane] <= x_i[lane];
                w_q[lane] <= fifo_q[words_consumed[0]][(int'(input_chunk_q[1:0]) << 6) + lane * 2 +: 2];
            end
    end
    endgenerate
endmodule
