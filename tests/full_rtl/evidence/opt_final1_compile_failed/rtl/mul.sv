module mul (
    input logic signed [15:0] a,
    input logic [15:0] b,
    input logic b_unsigned,
    input logic [5:0] rshift,
    output logic signed [31:0] product,
    output logic signed [15:0] result,
    output logic overflow
);
    import npu_pkg::*;
    logic signed [16:0] b_s17;
    logic signed [32:0] p33;
    logic signed [63:0] rounded;
    logic_mul #(.A_W(16), .B_W(17), .OUT_W(33), .SIGNED_A(1), .SIGNED_B(1)) u_bit_mul
        (.a(a), .b(b_s17), .product(p33));
    always_comb begin
        b_s17 = b_unsigned ? $signed({1'b0, b}) : $signed({b[15], b});

        product = p33[31:0];
        rounded = rne_shift64({{31{p33[32]}}, p33}, rshift);
        overflow = (rounded > 64'sh0000_0000_0000_7fff) || (rounded < - 64'sh0000_0000_0000_8000) || (b_unsigned && b > 16'h8000);
        result = sat_s16(rounded);
    end
endmodule

// Small arithmetic cell retained here after consolidating legacy helper files.
// Used by the arithmetic regression; no technology binding is required.
module addsub (
    input logic signed [15:0] a, b,
    input logic sub,
    output logic signed [16:0] wide,
    output logic signed [15:0] result,
    output logic overflow
);
    import npu_pkg::*;
    logic signed [16:0] b_ext;
    always_comb begin
        b_ext = {b[15], b};
        wide = {a[15], a} + (sub ? -b_ext : b_ext);
        overflow = wide[16] ^ wide[15];
        result = sat_s16({{47{wide[16]}}, wide});
    end
endmodule
