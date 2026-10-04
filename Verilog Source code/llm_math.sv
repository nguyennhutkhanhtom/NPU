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
    // Bit-product compressor trees and pair sums split arithmetic across edges.
    logic [9:0] valid_q;
    logic signed [23:0] a_q [0:31];
    logic signed [31:0] b_q [0:31];
    logic signed [32:0] partial_q [0:31][0:3];
    wire [32:0] partial_comb [0:31][0:3];
    genvar mul_lane, mul_part;
    generate
    for (mul_lane = 0; mul_lane < 32; mul_lane = mul_lane + 1) begin : g_mul_lane
        for (mul_part = 0; mul_part < 4; mul_part = mul_part + 1) begin : g_byte
            logic_mul #(.A_W(24), .B_W(8), .OUT_W(33), .SIGNED_A(1), .SIGNED_B(mul_part == 3)) u_mul
                (.a(a_q[mul_lane]), .b(b_q[mul_lane][(mul_part << 3) +: 8]), .product(partial_comb[mul_lane][mul_part]));
        end
    end
    endgenerate
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
                for (int part = 0; part < 4; part = part + 1)
                    partial_q[i][part] <= partial_comb[i][part];
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
