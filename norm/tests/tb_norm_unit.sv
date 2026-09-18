`timescale 1ns/1ps
module tb_norm_unit;
    `include "fixtures.svh"
    logic clk=0, rst_n=0, start=0;
    logic [15:0] x[31:0];
    wire [15:0] y[31:0];
    wire busy, done, overflow;
    logic [511:0] inputs[0:UNIT_CASES-1], expected[0:UNIT_CASES-1];
    logic flags[0:UNIT_CASES-1];
    logic [15:0] rms[0:UNIT_CASES-1];
    logic [23:0] sums[0:UNIT_CASES-1];
    logic [511:0] last_result='0;
    wire [511:0] result;
    int completions=0;
    always #5 clk=~clk;
    for(genvar i=0;i<32;i++) assign result[16*i+:16]=y[i];
    norm #(.LUT_FILE("normContent.mif")) dut(.*,.out(y));

    task automatic reset_dut;
        @(negedge clk); rst_n=0; start=0;
        #1;
        if(busy || done || overflow || result!==0) $fatal(1,"NORM reset failed");
        repeat(2) @(negedge clk);
        rst_n=1; last_result='0;
    endtask

    initial begin
        $readmemh("unit-input.hex", inputs);
        $readmemh("unit-expected.hex", expected);
        $readmemh("unit-flags.hex", flags);
        $readmemh("unit-rms.hex", rms);
        $readmemh("unit-sum.hex", sums);
        for(int i=0;i<32;i++) x[i]=0;
        reset_dut();
        // Abort separately in the RMS and division phases, then run a clean request.
        for(int phase=0;phase<2;phase++) begin
            @(negedge clk); start=1;
            for(int i=0;i<32;i++) x[i]=16'h8000;
            @(posedge clk); #1;
            if(phase==1) begin @(negedge clk); start=0; @(posedge clk); #1; end
            reset_dut();
            repeat(3) begin @(posedge clk); #1; if(done || busy) $fatal(1,"Stale completion after reset"); end
        end
        for(int test=0;test<UNIT_CASES;test++) begin
            @(negedge clk); start=1;
            for(int i=0;i<32;i++) x[i]=inputs[test][16*i+:16];
            @(posedge clk); #1;
            if(!busy || done || overflow) $fatal(1,"Start handshake case=%0d",test);
            if(dut.mean_sq_q17!==sums[test]) $fatal(1,"Lost mean LSB case=%0d",test);
            if(result!==last_result) $fatal(1,"Output changed before completion");
            @(negedge clk);
            // Change every live input and assert start while busy.
            for(int i=0;i<32;i++) x[i]=16'(test+i);
            start=1;
            @(posedge clk); #1;
            if(!busy || done || dut.rms_reg!==rms[test]) $fatal(1,"RMS scale/sqrt case=%0d",test);
            @(negedge clk); start=1;
            @(posedge clk); #1;
            if(busy || !done || result!==expected[test] || overflow!==flags[test])
                $fatal(1,"NORM case=%0d got=%h expected=%h overflow=%b/%b",test,result,expected[test],overflow,flags[test]);
            completions++;
            last_result=result;
            // Next iteration accepts at the earliest legal clock after done.
        end
        @(negedge clk); start=0;
        repeat(4) begin @(posedge clk); #1; if(done || busy || result!==last_result) $fatal(1,"Done pulse/output hold"); end
        $display("NORM_UNIT_PASS vectors=%0d lanes=%0d reset_phases=2 busy_start=ignored",completions,completions*32);
        $finish;
    end
    initial begin #2000000; $fatal(1,"Unit watchdog"); end
endmodule

module tb_norm_rom;
    logic clk=0, en=0;
    logic [15:0] x=0;
    wire [18:0] out;
    int signed raw, quantized;
    always #5 clk=~clk;
    Norm_Square_ROM #(.LUT_FILE("normContent.mif")) dut(.*);
    initial begin
        for(int bits=0;bits<65536;bits++) begin
            @(negedge clk); en=1; x=16'(bits);
            raw=$signed(x); quantized=raw >>> 6;
            @(posedge clk); #1;
            if(out!==19'(quantized*quantized)) $fatal(1,"ROM mismatch x=%h out=%h",x,out);
            @(negedge clk); en=0; x=~x;
            @(posedge clk); #1;
            if(out!==19'(quantized*quantized)) $fatal(1,"ROM enable did not hold");
        end
        $display("NORM_ROM_PASS inputs=65536 entries=1024 hold_checks=65536"); $finish;
    end
endmodule

module tb_norm_missing;
    logic clk=0, en=0;
    logic [15:0] x=0;
    wire [18:0] out;
    Norm_Square_ROM #(.LUT_FILE("intentionally-missing-norm.mif")) dut(.*);
    initial begin #10; $display("GUARD_MISSED"); $finish; end
endmodule
