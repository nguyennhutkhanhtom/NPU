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
    logic signed [63:0] rounded;
    logic signed [63:0] biased;
    always_comb begin
        product = $signed(acc) * $signed({1'b0, scale_m});
        rounded = rne_shift64({{22{product[41]}}, product}, scale_r);
        biased = rounded + {{32{bias[31]}}, bias};
        y_s32 = sat_s32(biased);
        y_s16 = sat_s16(biased);
        overflow = output_s32 ? (biased > 64'sh0000_0000_7fff_ffff || biased < - 64'sh0000_0000_8000_0000)
         : (biased > 64'sh0000_0000_0000_7fff || biased < - 64'sh0000_0000_0000_8000);
    end
endmodule
