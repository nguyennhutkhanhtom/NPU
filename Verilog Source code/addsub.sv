module addsub (
    input logic signed [15:0] a,
    input logic signed [15:0] b,
    input logic sub,
    output logic signed [16:0] wide,
    output logic signed [15:0] result,
    output logic overflow
);
    import npu_pkg::*;
    logic signed [16:0] b_ext;
    always_comb begin
        b_ext = {b[15], b};
        wide = {a[15], a} + (sub ? - b_ext : b_ext);
        overflow = wide[16] ^ wide[15];
        result = sat_s16({{47{wide[16]}}, wide});
    end
endmodule
