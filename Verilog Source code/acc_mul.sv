module acc_mul #(
    parameter int TERM_W = 9,
    parameter int NUM_INPUTS = 32,
    parameter int ACC_W = 18
) (
    input logic signed [TERM_W - 1 : 0] term [NUM_INPUTS - 1 : 0],
    output logic signed [ACC_W - 1 : 0] sum
);
    localparam int LEAVES = 2 ** $clog2(NUM_INPUTS);
    logic signed [ACC_W - 1 : 0] tree [0 : 2 * LEAVES - 2];
    integer i;
    always_comb begin
        for (i = 0;i < LEAVES;i = i + 1)
            if (i < NUM_INPUTS) tree[LEAVES - 1 + i] = {{(ACC_W - TERM_W){term[i][TERM_W - 1]}}, term[i]};
        else tree[LEAVES - 1 + i] = '0;
        for (i = LEAVES - 2;i >= 0;i = i - 1) tree[i] = tree[2 * i + 1] + tree[2 * i + 2];
        sum = tree[0];
    end
endmodule
