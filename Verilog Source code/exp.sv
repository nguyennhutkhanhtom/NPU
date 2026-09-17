module exp_row #(
    parameter DATA_WIDTH=16,
    parameter LUT_DEPTH=512,
    parameter INIT_FILE="exp_content.mif"
) (
    input logic [DATA_WIDTH-1:0] a,
    output logic [DATA_WIDTH-1:0] result
);
    
    logic [DATA_WIDTH-1:0] mem [0:LUT_DEPTH-1];
    logic [DATA_WIDTH-1:0] y;

    initial begin
        if (INIT_FILE != "") $readmemh(INIT_FILE, mem);
    end

    always_comb
    begin
        if($signed(a) >= 0)
            y = a + (2**(DATA_WIDTH-1));
        else 
            y = a - (2**(DATA_WIDTH-1));
    end

    assign result = mem[y];
    
endmodule