// Test-only replacement for the unrelated, known-broken 262144-cell TMATMUL.
// Any attempt to execute it FAILS the focused EXP/NORM top-level test.
module ternary_mul(input clk,rst_n,enable,input logic [511:0] matrix_in,ternary_matrix,
    output wire [511:0] matrix_out,input logic read_finish,output wire tmatmul_write);
    assign matrix_out='0;
    assign tmatmul_write=0;
    always @(posedge clk) if(rst_n && enable) $fatal(1,"TMATMUL is outside this focused integration test");
endmodule
