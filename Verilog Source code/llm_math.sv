// Shared fixed-point SIMD arithmetic for autonomous language inference.
// Payload registers are valid only while the control pipeline is active.
module llm_math (
    input logic clk, rst_n, start,
    input logic signed [23:0] a [0:31],
    input logic signed [31:0] b [0:31],
    output logic busy, done,
    output logic signed [55:0] product [0:31],
    output logic signed [60:0] sum
);
    // Byte products and pair sums split the logic-cell multiplier across edges.
    logic [9:0] valid_q;
    logic signed [23:0] a_q [0:31];
    logic signed [31:0] b_q [0:31];
    logic signed [32:0] partial_q [0:31][0:3];
    logic signed [40:0] pair_q [0:31][0:1];
    logic signed [56:0] level1 [0:15];
    logic signed [57:0] level2 [0:7];
    logic signed [58:0] level3 [0:3];
    logic signed [59:0] level4 [0:1];
    assign busy = |valid_q;
    assign done = valid_q[9];
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) valid_q <= 0;
        else valid_q <= {valid_q[8:0], start && !busy};
    end
    always_ff @(posedge clk) begin
        if (rst_n && start && !busy)
            for (int i = 0; i < 32; i = i + 1) begin
                a_q[i] <= a[i];
                b_q[i] <= b[i];
            end
        if (valid_q[0])
            for (int i = 0; i < 32; i = i + 1) begin
                for (int part = 0; part < 3; part = part + 1)
                    partial_q[i][part] <= a_q[i] * $signed({1'b0, b_q[i][part * 8 +: 8]});
                partial_q[i][3] <= a_q[i] * $signed(b_q[i][31:24]);
            end
        if (valid_q[1])
            for (int i = 0; i < 32; i = i + 1) begin
                pair_q[i][0] <= 41'(partial_q[i][0]) + (41'(partial_q[i][1]) <<< 8);
                pair_q[i][1] <= 41'(partial_q[i][2]) + (41'(partial_q[i][3]) <<< 8);
            end
        if (valid_q[2])
            for (int i = 0; i < 32; i = i + 1)
                product[i] <= 56'(pair_q[i][0]) + (56'(pair_q[i][1]) <<< 16);
        if (valid_q[3])
            for (int i = 0; i < 16; i = i + 1)
                level1[i] <= 57'(product[2 * i]) + 57'(product[2 * i + 1]);
        if (valid_q[4])
            for (int i = 0; i < 8; i = i + 1)
                level2[i] <= 58'(level1[2 * i]) + 58'(level1[2 * i + 1]);
        if (valid_q[5])
            for (int i = 0; i < 4; i = i + 1)
                level3[i] <= 59'(level2[2 * i]) + 59'(level2[2 * i + 1]);
        if (valid_q[6])
            for (int i = 0; i < 2; i = i + 1)
                level4[i] <= 60'(level3[2 * i]) + 60'(level3[2 * i + 1]);
        if (valid_q[7]) sum <= 61'(level4[0]) + 61'(level4[1]);
    end
endmodule
