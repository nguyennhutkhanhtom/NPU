module acc_mul #(
    parameter int DATA_WIDTH = 16,
    parameter int NUM_INPUTS = 512,
    parameter int ACC_WIDTH = DATA_WIDTH + $clog2(NUM_INPUTS)
)(
    input logic [DATA_WIDTH-1:0] mul_result [NUM_INPUTS-1:0],
    output logic [ACC_WIDTH-1:0] acc_result,
    output logic [ACC_WIDTH-1:0] acc_sum, acc_carry
);

    function automatic integer operand_count(input integer level);
        integer count;
        begin
            count = NUM_INPUTS;
            for (integer i = 0; i < level; i = i + 1)
                count = (count / 3) * 2 + count % 3;
            operand_count = count;
        end
    endfunction

    function automatic integer stage_count(input integer count);
        integer levels;
        begin
            levels = 0;
            while (count > 2) begin
                count = (count / 3) * 2 + count % 3;
                levels = levels + 1;
            end
            stage_count = levels;
        end
    endfunction

    localparam int STAGES = stage_count(NUM_INPUTS);
    genvar stage, i;

    // 3:2 compressors have no carry propagation across a word.
    // Keep both outputs when composing pipelined or iterative reductions.
    generate
        for (stage = 0; stage <= STAGES; stage = stage + 1) begin : reduction
            localparam int COUNT = operand_count(stage);
            logic [ACC_WIDTH-1:0] data [COUNT-1:0];
            if (stage == 0) begin : inputs_assign
                for (i = 0; i < COUNT; i = i + 1) begin : input_loop
                    assign data[i] = {{(ACC_WIDTH-DATA_WIDTH){mul_result[i][DATA_WIDTH-1]}}, mul_result[i]};
                end
            end
            else begin : compress
                localparam int PREVIOUS = operand_count(stage-1);
                for (i = 0; i < PREVIOUS/3; i = i + 1) begin : compressor
                    wire [ACC_WIDTH-1:0] a = reduction[stage-1].data[i*3];
                    wire [ACC_WIDTH-1:0] b = reduction[stage-1].data[i*3+1];
                    wire [ACC_WIDTH-1:0] c = reduction[stage-1].data[i*3+2];
                    assign data[i*2] = a ^ b ^ c;
                    assign data[i*2+1] = ((a & b) | (a & c) | (b & c)) << 1;
                end
                for (i = 0; i < PREVIOUS%3; i = i + 1) begin : remainder
                    assign data[(PREVIOUS/3)*2+i] = reduction[stage-1].data[(PREVIOUS/3)*3+i];
                end
            end
        end
        if (NUM_INPUTS == 1) begin : single_input
            assign acc_carry = '0;
        end
        else begin : multiple_inputs
            assign acc_carry = reduction[STAGES].data[1];
        end
    endgenerate

    assign acc_sum = reduction[STAGES].data[0];
    assign acc_result = acc_sum + acc_carry;

    // Exact signed sums need DATA_WIDTH+clog2(N). A smaller ACC_WIDTH
    // deliberately selects modulo arithmetic, but cannot truncate inputs.
    // synthesis translate_off
    initial begin
        if (DATA_WIDTH < 1 || NUM_INPUTS < 1 || ACC_WIDTH < DATA_WIDTH)
            $fatal(1, "Invalid accumulator parameters");
    end
    // synthesis translate_on
endmodule
