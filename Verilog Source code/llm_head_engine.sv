// Ordered vocabulary stream: one packed scale read per eight rows, then four
// int8 weight chunks per row. Eight reserved result slots bound memory/SIMD
// work; the parent retires tagged rows through exact scaling and selection.
module llm_head_engine (
    input logic clk, rst_n, start_i, cancel_i,
    output logic parameter_req_o,
    output logic [14:0] parameter_address_o,
    input logic parameter_valid_i,
    input logic [255:0] parameter_data_i,
    output logic operand_capture_o, math_issue_o,
    output logic [1:0] input_chunk_o,
    input logic sum_valid_i,
    input logic signed [60:0] sum_i,
    input logic result_ready_i,
    output logic result_valid_o, busy_o, done_o,
    output logic [11:0] row_o,
    output logic [23:0] coefficient_o,
    output logic signed [38:0] accumulator_o
);
    logic active_q;
    logic canceled_q;
    logic [5:0] parameter_pending_q, math_pending_q;
    logic [12:0] request_row_q, issued_rows_q, sum_row_q, retire_row_q;
    logic [11:0] response_row_q;
    logic [1:0] request_chunk_q, response_chunk_q, sum_chunk_q;
    logic request_scale_q, response_scale_q;
    logic [14:0] response_q;
    logic [255:0] scale_word_q;
    logic signed [38:0] sum_acc_q, result_q [0:7];
    logic [23:0] coefficient_q [0:7];
    wire result_pop = result_valid_o && result_ready_i;
    wire [12:0] reserved_rows = issued_rows_q - retire_row_q;
    assign busy_o = active_q;
    // Reserve a slot at chunk zero; later chunks retain that reservation.
    assign parameter_req_o = active_q && !cancel_i && !canceled_q && request_row_q < 4096 &&
        (request_scale_q || request_chunk_q != 0 || reserved_rows < 8);
    assign parameter_address_o = request_scale_q ?
        15'd23040 + {6'd0, request_row_q[11:3]} :
        {1'b0, request_row_q[11:0], request_chunk_q};
    assign operand_capture_o = active_q && !cancel_i && !canceled_q && parameter_valid_i && !response_scale_q;
    assign input_chunk_o = response_chunk_q;
    assign result_valid_o = active_q && !cancel_i && !canceled_q && retire_row_q < sum_row_q;
    assign row_o = retire_row_q[11:0];
    assign coefficient_o = coefficient_q[retire_row_q[2:0]];
    assign accumulator_o = result_q[retire_row_q[2:0]];
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active_q <= 0; done_o <= 0; math_issue_o <= 0;
            canceled_q <= 0; parameter_pending_q <= 0; math_pending_q <= 0;
            request_row_q <= 0; issued_rows_q <= 0; response_row_q <= 0;
            sum_row_q <= 0; retire_row_q <= 0;
            request_chunk_q <= 0; response_chunk_q <= 0; sum_chunk_q <= 0;
            request_scale_q <= 1; response_scale_q <= 1; response_q <= 0;
        end else begin
            done_o <= 0;
            math_issue_o <= operand_capture_o;
            if (active_q) begin
                case ({parameter_req_o, parameter_valid_i})
                    2'b10: parameter_pending_q <= parameter_pending_q + 1'b1;
                    2'b01: parameter_pending_q <= parameter_pending_q - 1'b1;
                    default: ;
                endcase
                case ({math_issue_o && !cancel_i, sum_valid_i})
                    2'b10: math_pending_q <= math_pending_q + 1'b1;
                    2'b01: math_pending_q <= math_pending_q - 1'b1;
                    default: ;
                endcase
            end
            if ((cancel_i || canceled_q) && active_q) begin
                canceled_q <= 1; math_issue_o <= 0;
                // Keep ownership until accepted memory/SIMD responses drain.
                if (parameter_pending_q == 0 && math_pending_q == 0) active_q <= 0;
            end
            else if (start_i && !active_q && !cancel_i) begin
                active_q <= 1;
                canceled_q <= 0; parameter_pending_q <= 0; math_pending_q <= 0;
                request_row_q <= 0; issued_rows_q <= 0; response_row_q <= 0;
                sum_row_q <= 0; retire_row_q <= 0;
                request_chunk_q <= 0; response_chunk_q <= 0; sum_chunk_q <= 0;
                request_scale_q <= 1; response_scale_q <= 1; response_q <= 0;
            end else if (active_q) begin
                if (parameter_req_o) begin
                    if (request_scale_q) request_scale_q <= 0;
                    else begin
                        request_chunk_q <= request_chunk_q + 1'b1;
                        if (request_chunk_q == 0) issued_rows_q <= issued_rows_q + 1'b1;
                        if (request_chunk_q == 3) begin
                            request_row_q <= request_row_q + 1'b1;
                            if (request_row_q[2:0] == 7) request_scale_q <= 1;
                        end
                    end
                end
                if (parameter_valid_i) begin
                    if (response_scale_q) response_scale_q <= 0;
                    else begin
                        response_q <= response_q + 1'b1;
                        response_chunk_q <= response_chunk_q + 1'b1;
                        if (response_chunk_q == 3) begin
                            response_row_q <= response_row_q + 1'b1;
                            if (response_row_q[2:0] == 7) response_scale_q <= 1;
                        end
                    end
                end
                if (sum_valid_i) begin
                    sum_chunk_q <= sum_chunk_q + 1'b1;
                    if (sum_chunk_q == 3) sum_row_q <= sum_row_q + 1'b1;
                end
                if (result_pop) begin
                    retire_row_q <= retire_row_q + 1'b1;
                    if (retire_row_q == 4095) begin active_q <= 0; done_o <= 1; end
                end
            end
        end
    end
    always_ff @(posedge clk)
        if (rst_n && !cancel_i && !canceled_q && active_q) begin
            if (parameter_valid_i && response_scale_q) scale_word_q <= parameter_data_i;
            if (operand_capture_o && response_chunk_q == 0)
                coefficient_q[response_row_q[2:0]] <= scale_word_q[{response_row_q[2:0], 5'b0} +: 24];
            if (sum_valid_i) begin
                if (sum_chunk_q == 0) sum_acc_q <= $signed(sum_i[38:0]);
                else sum_acc_q <= sum_acc_q + $signed(sum_i[38:0]);
                if (sum_chunk_q == 3)
                    result_q[sum_row_q[2:0]] <= sum_acc_q + $signed(sum_i[38:0]);
            end
        end
endmodule
