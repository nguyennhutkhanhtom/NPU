module mul #(parameter DATA_WIDTH=16, FRAC_WIDTH=DATA_WIDTH-4) (
    input logic [DATA_WIDTH-1:0] a [31:0],
    input logic [DATA_WIDTH-1:0] b [31:0],
    output logic [DATA_WIDTH-1:0] result [31:0],
    output logic overflow
);
    
    logic [2*DATA_WIDTH-1:0] mul_result [31:0];
    logic [31:0] overflow_tmp ;
    // Legacy Q4.F bit selection and overflow logic, intentionally NOT corrected.
    // Only widths change: default Q4.12 -> scaled Q4.4.
    initial begin
        if (DATA_WIDTH<5 || FRAC_WIDTH!=DATA_WIDTH-4)
            $fatal(1,"Legacy multiply parameterization requires Q4.F, F>=1");
    end
    // The result has 4 bit integer and FRAC_WIDTH fractional bits
    genvar i; 
    generate 
        for (i = 0; i < 32; i = i + 1) begin : rowwise_mul
            always_comb begin
                mul_result[i] = $signed(a[i]) * $signed(b[i]);
            end
				
				always_comb begin
					overflow_tmp[i] = |mul_result[i][2*DATA_WIDTH-2:2*FRAC_WIDTH+3];
					if(overflow_tmp[i])
						result[i] = {DATA_WIDTH{|mul_result[i][2*DATA_WIDTH-2:2*FRAC_WIDTH+3]}};
					else begin
						result[i][DATA_WIDTH-2:FRAC_WIDTH] = mul_result[i][2*FRAC_WIDTH+2:2*FRAC_WIDTH];
						result[i][DATA_WIDTH-1] = mul_result[i][2*DATA_WIDTH-1];
						result[i][FRAC_WIDTH-1:0] = mul_result[i][2*FRAC_WIDTH+3 -: FRAC_WIDTH];
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
    //     overflow = |mul_result[2*DATA_WIDTH-2:2*FRAC_WIDTH+3];
    //     if(|mul_result[2*DATA_WIDTH-2:2*FRAC_WIDTH+3])
    //         result = 16{mul_result[30]};
    //     else begin
    //         result[14:12] = mul_result[26:24];
    //         result[15] = mul_result[31];
    //         result[11:0] = mul_result[27:16];
    //     end
    // end

endmodule