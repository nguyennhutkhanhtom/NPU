`timescale 1ns/1ps
module tb_norm;
    parameter W=8;
    localparam WW=W*32;
    logic clk=0,rst_n=0,start=0,iv=0,ordy=0;
    logic [WW-1:0] din,dout;
    wire irdy,ov,done,overflow;
    logic [WW-1:0] inputs[0:79],expected[0:79],held;
    always #5 clk=~clk;
    norm #(.DATA_WIDTH(W),.FRAC_WIDTH(W-4)) dut(
        .clk(clk),.rst_n(rst_n),.start(start),.in_valid(iv),.out_ready(ordy),
        .data_in(din),.in_ready(irdy),.out_valid(ov),.done(done),.overflow(overflow),.data_out(dout));
    initial begin : run_tests
        int sent,received,ticks;
        bit holding;
        $readmemh(W==8 ? "functional/assets/rms_input_8.hex" : "functional/assets/rms_input_16.hex",inputs);
        $readmemh(W==8 ? "functional/assets/rms_golden_8.hex" : "functional/assets/rms_golden_16.hex",expected);
        repeat(3) @(negedge clk);rst_n=1;
        // Reset a partially captured vector before the numeric cases.
        start=1;@(negedge clk);start=0;iv=1;din='1;
        repeat(4) @(negedge clk);
        rst_n=0;iv=0;repeat(2) @(negedge clk);rst_n=1;
        for(int test=0;test<5;test++) begin
            @(negedge clk);start=1;
            @(negedge clk);start=0;sent=0;ticks=0;
            while(sent<16) begin
                @(negedge clk);iv=ticks%3!=0;din=inputs[test*16+sent];
                @(posedge clk);if(iv && irdy) sent++;
                #1;ticks++;
            end
            @(negedge clk);iv=0;received=0;ticks=0;holding=0;
            while(!done) begin
                @(negedge clk);ordy=ticks%4!=0;
                @(posedge clk);
                if(holding && dout!==held) $fatal(1,"RMS output changed under stall");
                if(ov && ordy) begin
                    if(received>=16 || dout!==expected[test*16+received])
                        $fatal(1,"RMS W=%0d case=%0d word=%0d got=%h expected=%h",
                            W,test,received,dout,expected[test*16+received]);
                    received++;
                end
                holding=ov&&!ordy;held=dout;
                #1;ticks++;
                if(ticks>100) $fatal(1,"RMS timeout");
            end
            if(received!=16) $fatal(1,"RMS output count");
            @(negedge clk);ordy=0;
        end
        $display("NORM_PASS W=%0d vectors=5 reset=1 bubbles=1",W);$finish;
    end
    initial begin #50000;$fatal(1,"NORM watchdog");end
endmodule
