module norm #(parameter inWidth=16, dataWidth=16, parameter INIT_FILE="norm.mif") (
    input   [inWidth-1:0]   x,
    output  [dataWidth-1:0]  out
    );
    
    reg [dataWidth-1:0] mem [2**inWidth-1:0];
    reg [inWidth-1:0] y;
	
	initial
	begin
		if (INIT_FILE != "") $readmemb(INIT_FILE,mem);
	end
    
    always_comb
    begin
        if($signed(x) >= 0)
            y = x + (2**(inWidth-1));
        else 
            y = x - (2**(inWidth-1));
    end
    
    assign out = mem[y];
    
endmodule
