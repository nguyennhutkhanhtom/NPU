// Ordered vocabulary-row stream. Each eight-row group requests its packed
// scale word, then four int8 weight words per row; at most READ_CREDITS reads
// are outstanding and responses return in issue order. Weight words request
// parent operand capture and shared SIMD issue. Row sums retire in order with
// the row's U24 scale; the parent owns RNE, sampling, PRNG order and selection.
// Cancellation drains accepted reads and SIMD sums.
module llm_head_engine #(parameter int SCALE_BASE = 23040) (
    input logic clk, rst_n, start_i, cancel_i,
    output logic busy_o,
    output logic parameter_req_o,
    output logic [14:0] parameter_address_o,
    input logic parameter_valid_i,
    input logic [255:0] parameter_data_i,
    output logic operand_capture_o, math_issue_o,
    output logic [1:0] input_chunk_o,
    input logic sum_valid_i,
    input logic signed [60:0] sum_i,
    output logic result_valid_o,
    output logic signed [38:0] accumulator_o,
    output logic [23:0] coefficient_o
);
    genvar slot, entry;
    localparam int READ_CREDITS = 8;
    typedef enum logic [1:0] {IDLE, RUN, DRAIN} state_t;
    state_t state;
    // Request, response and retirement walk the same row/chunk sequence.
    logic [12:0] request_row_q;
    logic [11:0] response_row_q, retire_row_q;
    logic [1:0] request_chunk_q, response_chunk_q, sum_chunk_q;
    logic request_scale_q, response_scale_q;
    logic [3:0] reads_pending_q, sums_pending_q;
    logic signed [38:0] accumulator_q;
    // Group G overwrites slot G[0] after the 32 in-order weight responses of
    // group G-1; group G-2's last row retired ten edges after its own final
    // response (capture, issue, SIMD E8), so it no longer reads that slot.
    logic [23:0] scale_q [0:1][0:7];
    wire response = state != IDLE && parameter_valid_i && reads_pending_q != 0;
    wire scale_capture = response && response_scale_q;
    wire sum_accept = state != IDLE && sum_valid_i && sums_pending_q != 0;
    wire row_accept = state == RUN && !cancel_i && sum_accept;
    wire row_retire = row_accept && sum_chunk_q == 3;
    assign busy_o = state != IDLE;
    assign parameter_req_o = state == RUN && !cancel_i && !request_row_q[12] &&
        reads_pending_q < 4'(READ_CREDITS);
    assign parameter_address_o = request_scale_q ? 15'(SCALE_BASE + int'(request_row_q[11:3])) :
        {1'b0, request_row_q[11:0], request_chunk_q};
    assign operand_capture_o = state == RUN && !cancel_i && response && !response_scale_q;
    assign input_chunk_o = response_chunk_q;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE; math_issue_o <= 0; result_valid_o <= 0;
            request_row_q <= 0; request_chunk_q <= 0; request_scale_q <= 0;
            response_row_q <= 0; response_chunk_q <= 0; response_scale_q <= 0;
            retire_row_q <= 0; sum_chunk_q <= 0; reads_pending_q <= 0; sums_pending_q <= 0;
        end else begin
            math_issue_o <= operand_capture_o;
            result_valid_o <= row_retire;
            if (state == IDLE) begin
                if (start_i && !cancel_i) begin
                    state <= RUN;
                    request_row_q <= 0; request_chunk_q <= 0; request_scale_q <= 1;
                    response_row_q <= 0; response_chunk_q <= 0; response_scale_q <= 1;
                    retire_row_q <= 0; sum_chunk_q <= 0; reads_pending_q <= 0; sums_pending_q <= 0;
                end
            end else begin
                case ({parameter_req_o, response})
                    2'b10: reads_pending_q <= reads_pending_q + 1'b1;
                    2'b01: reads_pending_q <= reads_pending_q - 1'b1;
                    default: ;
                endcase
                case ({math_issue_o, sum_accept})
                    2'b10: sums_pending_q <= sums_pending_q + 1'b1;
                    2'b01: sums_pending_q <= sums_pending_q - 1'b1;
                    default: ;
                endcase
                if (parameter_req_o) begin
                    if (request_scale_q) request_scale_q <= 0;
                    else begin
                        request_chunk_q <= request_chunk_q + 1'b1;
                        if (request_chunk_q == 3) begin
                            request_row_q <= request_row_q + 1'b1;
                            request_scale_q <= request_row_q[2:0] == 7;
                        end
                    end
                end
                if (response) begin
                    if (response_scale_q) response_scale_q <= 0;
                    else begin
                        response_chunk_q <= response_chunk_q + 1'b1;
                        if (response_chunk_q == 3) begin
                            response_row_q <= response_row_q + 1'b1;
                            response_scale_q <= response_row_q[2:0] == 7;
                        end
                    end
                end
                if (row_accept) begin
                    sum_chunk_q <= sum_chunk_q + 1'b1;
                    if (sum_chunk_q == 3) retire_row_q <= retire_row_q + 1'b1;
                end
                if (state == RUN && (cancel_i || (row_retire && retire_row_q == 4095))) state <= DRAIN;
                else if (state == DRAIN && reads_pending_q == 0 && sums_pending_q == 0 && !math_issue_o)
                    state <= IDLE;
            end
        end
    end
    always_ff @(posedge clk)
        if (rst_n) begin
            if (state == IDLE && start_i && !cancel_i) accumulator_q <= 0;
            else if (row_accept) begin
                if (sum_chunk_q == 3) accumulator_q <= 0;
                else accumulator_q <= accumulator_q + $signed(sum_i[38:0]);
            end
            if (row_retire) begin
                accumulator_o <= accumulator_q + $signed(sum_i[38:0]);
                coefficient_o <= scale_q[retire_row_q[3]][retire_row_q[2:0]];
            end
        end
    // Each 32-bit slot carries a U24 scale; slot bits [31:24] are unused.
    generate
    for (slot = 0; slot < 2; slot = slot + 1) begin : g_scale_slot
        for (entry = 0; entry < 8; entry = entry + 1) begin : g_scale_row
            always_ff @(posedge clk)
                if (rst_n && scale_capture && response_row_q[3] == 1'(slot))
                    scale_q[slot][entry] <= parameter_data_i[entry * 32 +: 24];
        end
    end
    endgenerate
endmodule
