module div (
    input logic [15:0] a [31:0],
    input logic [15:0] b [31:0],
    output logic [15:0] result [31:0]
);

    genvar i;
    generate
        for (i = 0; i < 32; i = i + 1) begin : rowwise_div
            always_comb begin
                result[i] = $signed(a[i]) / $signed(b[i]);
			end
//				div_block div(
        end
    endgenerate

endmodule