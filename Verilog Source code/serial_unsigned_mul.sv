// One adder reused for exactly B_WIDTH cycles. No '*' datapath operator.
module serial_unsigned_mul #(parameter A_WIDTH=16, B_WIDTH=19)(
    input logic clk,rst_n,start,
    input logic [A_WIDTH-1:0] a,
    input logic [B_WIDTH-1:0] b,
    output logic busy,done,
    output logic [A_WIDTH+B_WIDTH-1:0] result
);
    localparam P=A_WIDTH+B_WIDTH;
    localparam CW=(B_WIDTH<2)?1:$clog2(B_WIDTH);
    logic [P-1:0] shifted_a,acc;
    logic [B_WIDTH-1:0] shifted_b;
    logic [CW-1:0] count;
    wire [P-1:0] next_acc=acc+(shifted_b[0] ? shifted_a : {P{1'b0}});
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            busy<=0;done<=0;result<='0;shifted_a<='0;shifted_b<='0;acc<='0;count<='0;
        end else begin
            done<=0;
            if(start && !busy) begin
                busy<=1;acc<='0;shifted_a<={{B_WIDTH{1'b0}},a};shifted_b<=b;count<='0;
            end else if(busy) begin
                acc<=next_acc;shifted_a<=shifted_a<<1;shifted_b<=shifted_b>>1;
                if(count==CW'(B_WIDTH-1)) begin busy<=0;done<=1;result<=next_acc;end
                else count<=count+1'b1;
            end
        end
    end
endmodule
