`timescale 1ns/1ps
module tb_norm;
    parameter W=8;
    localparam WW=W*32,CASES=24;
    logic clk=0,rst_n=0,start=0,iv=0,ordy=0;
    logic [WW-1:0] din;
    wire [WW-1:0] dout;
    wire sr,busy,irdy,ov,done,overflow;
    logic [WW-1:0] inputs[0:CASES*16-1],expected[0:CASES*16-1];
    logic flags[0:CASES-1];
    always #5 clk=~clk;
    norm #(.DATA_WIDTH(W)) dut(.clk(clk),.rst_n(rst_n),.start(start),.start_ready(sr),.busy(busy),
        .data_in(din),.in_valid(iv),.in_ready(irdy),.data_out(dout),.out_valid(ov),.out_ready(ordy),.done(done),.overflow(overflow));
    task automatic reset_dut;
        @(negedge clk);rst_n=0;start=0;iv=0;ordy=0;
        repeat(2) @(negedge clk);
        if(busy || ov || done || !sr) $fatal(1,"Reset did not abort NORM");
        rst_n=1;
    endtask
    task automatic begin_vector;
        @(negedge clk);if(!sr) $fatal(1,"Start not ready");start=1;
        @(negedge clk);start=0;
    endtask
    initial begin : tests
        int sent,received,cycles,total_cycles;
        logic [WW-1:0] held;
        bit holding;
        $readmemh($sformatf("nonlinear/assets/norm_input_%0d.hex",W),inputs);
        $readmemh($sformatf("nonlinear/assets/norm_expected_%0d.hex",W),expected);
        $readmemh($sformatf("nonlinear/assets/norm_flags_%0d.hex",W),flags);
        reset_dut();
        // Abort while the shared shift/add engine is busy, then restart cleanly.
        begin_vector();iv=1;din='1;
        repeat(7) @(negedge clk);
        reset_dut();total_cycles=0;
        for(int test=0;test<CASES;test++) begin
            begin_vector();sent=0;received=0;cycles=0;holding=0;
            while(!done) begin
                @(negedge clk);
                iv=(sent<16 && cycles%5!=0);
                if(sent<16) din=inputs[test*16+sent];
                ordy=(cycles%7>=3);
                // Requests while busy are ignored and must not overwrite context.
                start=(cycles==37);
                @(posedge clk);
                if(iv&&irdy) sent++;
                if(holding && (!ov || dout!==held)) $fatal(1,"Output changed while stalled");
                if(ov&&ordy) begin
                    if(received>=16 || dout!==expected[test*16+received])
                        $fatal(1,"NORM W=%0d case=%0d word=%0d got=%h expected=%h",W,test,received,dout,expected[test*16+received]);
                    received++;
                end
                holding=ov&&!ordy;held=dout;
                #1;cycles++;
                if(cycles>40000) $fatal(1,"NORM watchdog case=%0d",test);
            end
            if(sent!=16 || received!=16 || overflow!==flags[test] || busy || !sr)
                $fatal(1,"NORM completion/flags case=%0d sent=%0d received=%0d ov=%b exp=%b",test,sent,received,overflow,flags[test]);
            @(negedge clk);iv=0;ordy=0;start=0;
            @(posedge clk);#1;if(done) $fatal(1,"done is not a pulse");
            total_cycles+=cycles;
        end
        // Abort while output valid is held; stale result must disappear.
        begin_vector();sent=0;ordy=0;
        while(!ov) begin
            @(negedge clk);iv=sent<16;din='0;
            @(posedge clk);if(iv&&irdy) sent++;
            #1;
        end
        reset_dut();
        $display("NORM_PASS W=%0d vectors=%0d words=%0d cycles=%0d resets=2 stalls=1",W,CASES,CASES*16,total_cycles);$finish;
    end
    initial begin #20000000; $fatal(1,"global watchdog");end
endmodule
