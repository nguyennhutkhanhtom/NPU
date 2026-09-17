module addsub(  
    input logic [15:0] a,
    input logic [15:0] b,
    input logic       select,
    output logic cout, overflow,
    output logic [15:0] sum
    );
    logic c;

    assign {c, sum} = a + b ^ {16{select}} + select;
    assign cout = c ^ select;
    assign overflow = (a[15] ^ sum[15]) & !(a[15] ^ b[15] ^ select);
    
endmodule