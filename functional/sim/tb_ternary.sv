`timescale 1ns/1ps
module tb_ternary;
    parameter W=8;
    localparam WW=W*32,PER=WW/2,MW=512*512/PER,LO=-(1<<(W-1)),HI=(1<<(W-1))-1;
    logic clk=0,rst_n=0,start=0,av=0,tv=0,ordy=0;
    logic [WW-1:0] activation,weights,result,held;
    wire ardy,trdy,valid,done,overflow;
    always #5 clk=~clk;
    ternary_mul #(.DATA_WIDTH(W)) dut(.clk(clk),.rst_n(rst_n),.enable(start),
        .matrix_in(activation),.ternary_matrix(weights),.matrix_valid(av),.ternary_valid(tv),
        .output_ready(ordy),.matrix_ready(ardy),.ternary_ready(trdy),
        .matrix_out(result),.tmatmul_write(valid),.done(done),.overflow(overflow));
    function automatic int sample(input int test,input int col);
        case(test)
            0: return col%31-15;
            1: return LO;
            2: return col%7-3;
            default: return col%2 ? LO : HI;
        endcase
    endfunction
    function automatic int weight(input int test,input int row,input int col);
        case(test)
            0: return row==col ? 1 : 0;
            1: return -1;
            2: return (col==(row+511)%512 ? -1 : 0)+(col==(row+17)%512 ? 1 : 0);
            default: return 1;
        endcase
    endfunction
    initial begin : run_tests
        int ca,ct,ticks,cw;
        longint signed total,expected;
        bit holding,expected_overflow;
        repeat(3) @(negedge clk);rst_n=1;
        // Aborted capture must not leak stale buffers into a later transaction.
        start=1;@(negedge clk);start=0;av=1;tv=1;activation='1;weights='0;
        repeat(4) @(negedge clk);rst_n=0;av=0;tv=0;
        repeat(2) @(negedge clk);rst_n=1;
        for(int test=0;test<4;test++) begin
            @(negedge clk);start=1;
            @(negedge clk);start=0;ca=0;ct=0;ticks=0;
            while(ca<16 || ct<MW) begin
                @(negedge clk);av=ca<16 && ticks%3!=0;tv=ct<MW && ticks%4!=0;
                for(int lane=0;lane<32;lane++) activation[lane*W+:W]=W'(sample(test,ca*32+lane));
                for(int k=0;k<PER;k++) weights[k*2+:2]=2'(weight(test,(ct*PER+k)/512,(ct*PER+k)%512));
                @(posedge clk);if(av && ardy) ca++;if(tv && trdy) ct++;
                #1;ticks++;
            end
            @(negedge clk);av=0;tv=0;cw=0;ticks=0;holding=0;
            while(!done) begin
                @(negedge clk);ordy=ticks%3!=0;
                @(posedge clk);
                if(holding && result!==held) $fatal(1,"TM output not stable");
                if(valid && ordy) begin
                    expected_overflow=0;
                    for(int lane=0;lane<32;lane++) begin
                        total=0;
                        for(int col=0;col<512;col++) total+=weight(test,cw*32+lane,col)*sample(test,col);
                        expected_overflow|=total>HI || total<LO;
                        expected=total>HI ? HI : total<LO ? LO : total;
                        if(cw>=16 || result[lane*W+:W]!==W'(expected))
                            $fatal(1,"TM W=%0d case=%0d row=%0d got=%h expected=%h",W,test,cw*32+lane,result[lane*W+:W],W'(expected));
                    end
                    if(overflow!==expected_overflow) $fatal(1,"TM overflow flag");
                    cw++;
                end
                holding=valid&&!ordy;held=result;
                #1;ticks++;
                if(ticks>100) $fatal(1,"TM write timeout");
            end
            if(cw!=16) $fatal(1,"TM output count");
            @(negedge clk);ordy=0;
        end
        $display("TERNARY_PASS W=%0d matrices=4 reset=1 independent_bubbles=1",W);$finish;
    end
    initial begin #300000;$fatal(1,"TM watchdog");end
endmodule
