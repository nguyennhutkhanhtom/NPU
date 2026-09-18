`timescale 1ns/1ps
module tb_exhaustive;
    parameter int SAT=0;
    logic clk=0,rst_n=0,start=0,av=0,tv=0;
    logic [7:0] activation,weights;
    wire [7:0] result;
    wire ar,tr,valid,done;
    int cases=0;
    always #5 clk=~clk;
    ternary_mul #(.DATA_WIDTH(4),.LANES(2),.MATRIX_ROWS(1),.MATRIX_COLS(2),
        .DOT_LANES(1),.REDUCE_GROUP(1),.SATURATE(SAT)) dut (
        .clk(clk),.rst_n(rst_n),.enable(start),.matrix_in(activation),.ternary_matrix(weights),
        .matrix_valid(av),.ternary_valid(tv),.output_ready(1'b1),.matrix_ready(ar),.ternary_ready(tr),
        .matrix_out(result),.tmatmul_write(valid),.done(done),.busy(),.overflow());
    initial begin
        int expected;
        repeat(2) @(negedge clk);rst_n=1;
        for(int a=-8;a<8;a++)
            for(int b=-8;b<8;b++)
                for(int weights_code=0;weights_code<16;weights_code++) begin
                    @(negedge clk);start=1;
                    @(negedge clk);start=0;av=1;tv=1;activation={4'(b),4'(a)};weights={4'hf,4'(weights_code)};
                    @(negedge clk);av=0;tv=0;
                    expected=0;
                    case(weights_code%4) 1:expected+=a; 3:expected-=a; endcase
                    case(weights_code/4) 1:expected+=b; 3:expected-=b; endcase
                    if(SAT && expected>7) expected=7;
                    if(SAT && expected< -8) expected=-8;
                    while(!valid) @(negedge clk);
                    if(result!=={4'b0,4'(expected)}) $fatal(1,"Exhaustive a=%0d b=%0d w=%0h",a,b,weights_code);
                    @(negedge clk);if(!done) $fatal(1,"Exhaustive completion");
                    cases++;
                end
        $display("EXHAUSTIVE_PASS W=4 C=2 SAT=%0d cases=%0d",SAT,cases);$finish;
    end
    initial begin #1000000;$fatal(1,"Exhaustive watchdog");end
endmodule
