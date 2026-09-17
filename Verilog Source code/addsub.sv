module addsub #(parameter DATA_WIDTH=16) (  
    input logic [DATA_WIDTH-1:0] a,
    input logic [DATA_WIDTH-1:0] b,
    input logic       select,
    output logic cout, overflow,
    output logic [DATA_WIDTH-1:0] sum
    );
    logic c;

    assign {c, sum} = a + b ^ {DATA_WIDTH{select}} + select;
    assign cout = c ^ select;
    assign overflow = (a[DATA_WIDTH-1] ^ sum[DATA_WIDTH-1]) & !(a[DATA_WIDTH-1] ^ b[DATA_WIDTH-1] ^ select);
    
endmodule