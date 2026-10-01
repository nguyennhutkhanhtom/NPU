module postscale (
    input logic signed [17:0] acc,
    input logic [23:0] scale_m,
    input logic [5:0] scale_r,
    input logic signed [31:0] bias,
    input logic output_s32,
    output logic signed [31:0] y_s32,
    output logic signed [15:0] y_s16,
    output logic overflow
);
    import npu_pkg::*;
    logic signed [41:0] product;
    logic signed [41:0] rounded;
    always_comb begin
        product = $signed(acc) * $signed({1'b0, scale_m});
        rounded = rne_shift42(product, scale_r);
    end
    postscale_finish u_finish(.rounded(rounded), .bias(bias),
        .output_s32(output_s32), .y_s32(y_s32), .y_s16(y_s16),
        .overflow(overflow));
endmodule

// Reused by the combinational reference interface above and the registered
// ternary datapath. An S42 rounded product plus S32 bias fits exactly in S43.
module postscale_finish (
    input logic signed [41:0] rounded,
    input logic signed [31:0] bias,
    input logic output_s32,
    output logic signed [31:0] y_s32,
    output logic signed [15:0] y_s16,
    output logic overflow
);
    import npu_pkg::*;
    logic signed [42:0] biased;
    always_comb begin
        biased = {rounded[41], rounded} + {{11{bias[31]}}, bias};
        y_s32 = sat_s32(64'(biased));
        y_s16 = sat_s16(64'(biased));
        overflow = output_s32 ? (biased > 43'sd2147483647 || biased < -43'sd2147483648)
         : (biased > 43'sd32767 || biased < -43'sd32768);
    end
endmodule
