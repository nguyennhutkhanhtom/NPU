module mul(
    input logic [15:0] a [31:0],
    input logic [15:0] b [31:0],
    output logic [15:0] result [31:0],
    output logic overflow
);
    
    logic [31:0] mul_result [31:0];
    logic [31:0] overflow_tmp ;
    // The result has 4 bit integer and 12 bit fractional part
    genvar i; 
    generate 
        for (i = 0; i < 32; i = i + 1) begin : rowwise_mul
            always_comb begin
                mul_result[i] = $signed(a[i]) * $signed(b[i]);
            end
				
				always_comb begin
					overflow_tmp[i] = |mul_result[i][30:27];
					if(overflow_tmp[i])
						result[i] = {16{|mul_result[i][30:27]}};
					else begin
						result[i][14:12] = mul_result[i][26:24];
						result[i][15] = mul_result[i][31];
						result[i][11:0] = mul_result[i][27:16];
					end
				end
        end
    endgenerate

    assign overflow = |overflow_tmp;

    // always_comb begin
    //     mul_result = $signed(a) * $signed(b);
    // end
    
    // // Rounding the result to 4Q12
    // always_comb begin
    //     overflow = |mul_result[30:27];
    //     if(|mul_result[30:27])
    //         result = 16{mul_result[30]};
    //     else begin
    //         result[14:12] = mul_result[26:24];
    //         result[15] = mul_result[31];
    //         result[11:0] = mul_result[27:16];
    //     end
    // end

endmodule