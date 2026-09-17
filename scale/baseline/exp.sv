module exp_row(
    input logic [15:0] a,
    output logic [15:0] result
);
    
    logic [15:0] mem [0:511];
    logic [15:0] y;

    initial begin
        $readmemh("exp_content.mif", mem);
    end

    always_comb
    begin
        if($signed(a) >= 0)
            y = a + (2**(15));
        else 
            y = a - (2**(15));
    end

    assign result = mem[y];
    
endmodule