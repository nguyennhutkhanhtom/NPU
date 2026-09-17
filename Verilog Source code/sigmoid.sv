module sigmoid #(parameter inWidth=16, dataWidth=16) (
    input  logic [15:0] x,      // Q4.12
    output logic [15:0] out      // Q4.12
    );
    
    logic [15:0] mem [0:1023];

    logic [9:0] x_lut;
    logic [9:0] y;

    initial begin
        $readmemb("sigContent.mif", mem);
    end

    assign x_lut = x[15:6];

    always_comb begin
        if ($signed(x_lut) >= 0)
            y = x_lut + 10'd512;
        else
            y = x_lut - 10'd512;
    end

    assign out = mem[y];

endmodule
