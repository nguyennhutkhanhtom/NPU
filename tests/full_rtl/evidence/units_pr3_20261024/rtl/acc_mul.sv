module acc_mul #(
    parameter int TERM_W = 9,
    parameter int NUM_INPUTS = 32,
    parameter int ACC_W = 18
) (
    input logic signed [TERM_W - 1 : 0] term [NUM_INPUTS - 1 : 0],
    output logic signed [ACC_W - 1 : 0] sum
);
    localparam int LEVELS = $clog2(NUM_INPUTS);
    localparam int LEAVES = 2 ** LEVELS;
    // Each tree level needs just one extra sign bit. Capping at ACC_W keeps
    // the original modulo-2^ACC_W behavior when the caller requests truncation.
    genvar level, n;
    generate
    for (level = 0; level <= LEVELS; level = level + 1) begin : g_level
        localparam int WIDTH = (TERM_W + level < ACC_W) ? TERM_W + level : ACC_W;
        localparam int COUNT = LEAVES >> level;
        logic signed [WIDTH - 1:0] node [0:COUNT - 1];
        for (n = 0; n < COUNT; n = n + 1) begin : g_node
            if (level == 0) begin : g_leaf
                if (n < NUM_INPUTS) assign node[n] = term[n];
                else assign node[n] = '0;
            end else begin : g_add
                assign node[n] = $signed(g_level[level - 1].node[2 * n]) +
                    $signed(g_level[level - 1].node[2 * n + 1]);
            end
        end
    end
    endgenerate
    assign sum = g_level[LEVELS].node[0];
endmodule
