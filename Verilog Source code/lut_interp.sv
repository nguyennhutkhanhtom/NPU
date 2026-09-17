// Short unsigned product using a statically elaborated balanced adder tree.
// No runtime loop, inferred multiplier operator, or combinational feedback.
module lut_interp #(parameter A_WIDTH=16, B_WIDTH=7)(
    input logic [A_WIDTH-1:0] a,
    input logic [B_WIDTH-1:0] b,
    output wire [A_WIDTH+B_WIDTH-1:0] product
);
    localparam P=A_WIDTH+B_WIDTH;
    localparam LEAVES=1<<$clog2(B_WIDTH);
    wire [P-1:0] tree[1:2*LEAVES-1];
    generate
        for(genvar i=0;i<LEAVES;i=i+1) begin : partial
            if(i<B_WIDTH) assign tree[LEAVES+i]=b[i] ? ({{B_WIDTH{1'b0}},a} << i) : '0;
            else assign tree[LEAVES+i]='0;
        end
        for(genvar i=1;i<LEAVES;i=i+1) begin : reduce
            assign tree[i]=tree[2*i]+tree[2*i+1];
        end
    endgenerate
    assign product=tree[1];
endmodule
