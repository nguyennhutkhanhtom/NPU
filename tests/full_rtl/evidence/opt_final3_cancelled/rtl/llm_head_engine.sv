// Four ordered int8 weight chunks per vocabulary row. The parent owns scaling
// and sampling; this engine owns memory issue, SIMD response count and dot sum.
module llm_head_engine (
    input logic clk, rst_n, start_i, cancel_i,
    input logic [11:0] vocabulary_i,
    output logic parameter_req_o,
    output logic [14:0] parameter_address_o,
    input logic parameter_valid_i,
    output logic operand_capture_o, math_issue_o,
    output logic [1:0] input_chunk_o,
    input logic sum_valid_i,
    input logic signed [60:0] sum_i,
    output logic done_o,
    output logic signed [38:0] accumulator_o
);
    logic active_q;
    logic [11:0] vocabulary_q;
    logic [2:0] request_q, response_q, sum_q;
    assign parameter_req_o = active_q && request_q < 4;
    assign parameter_address_o = {1'b0, vocabulary_q, request_q[1:0]};
    assign operand_capture_o = active_q && parameter_valid_i && response_q < 4;
    assign input_chunk_o = response_q[1:0];
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active_q <= 0; done_o <= 0; math_issue_o <= 0;
            request_q <= 0; response_q <= 0; sum_q <= 0;
        end else begin
            done_o <= 0;
            math_issue_o <= operand_capture_o;
            if (cancel_i) begin active_q <= 0; math_issue_o <= 0; end
            else if (start_i && !active_q) begin
                active_q <= 1; request_q <= 0; response_q <= 0; sum_q <= 0;
            end else if (active_q) begin
                if (parameter_req_o) request_q <= request_q + 1'b1;
                if (operand_capture_o) response_q <= response_q + 1'b1;
                if (sum_valid_i) begin
                    sum_q <= sum_q + 1'b1;
                    if (sum_q == 3) begin active_q <= 0; done_o <= 1; end
                end
            end
        end
    end
    always_ff @(posedge clk)
        if (rst_n && !cancel_i) begin
            if (start_i && !active_q) begin vocabulary_q <= vocabulary_i; accumulator_o <= 0; end
            else if (active_q && sum_valid_i) accumulator_o <= accumulator_o + $signed(sum_i[38:0]);
        end
endmodule
