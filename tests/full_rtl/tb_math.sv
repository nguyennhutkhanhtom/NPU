`timescale 1ns/1ps
module tb_llm_math;
    import llm_pkg::*;
    logic clk=0, rst_n=0, start=0, busy, done;
    logic signed [23:0] a [0:31];
    logic signed [31:0] b [0:31];
    logic signed [55:0] product [0:31];
    logic signed [60:0] sum;
    logic signed [127:0] expected_product [0:31], expected_sum;
    integer checks=0, clocks,table_checks=0,sample_integer;
    real sample_real;
    llm_math dut(.*);
    always #5 clk=~clk;
    task automatic check;
        expected_sum=0;
        for(integer i=0;i<32;i++) begin
            expected_product[i]=128'(a[i])*128'(b[i]);
            expected_sum+=expected_product[i];
        end
        @(negedge clk);start=1;
        @(negedge clk);start=0;clocks=0;
        while(!done && clocks<10) begin
            for(integer i=0;i<32;i++) begin a[i]=$urandom;b[i]=$urandom;end
            start=clocks==1; // Busy requests must not replace this transaction.
            @(negedge clk);start=0;clocks++;
        end
        if(!done || clocks!=7) $fatal(1,"SIMD latency clocks=%0d",clocks);
        if(sum!==expected_sum[60:0]) $fatal(1,"SIMD sum expected=%h actual=%h",expected_sum,sum);
        for(integer i=0;i<32;i++)
            if(product[i]!==expected_product[i][55:0]) $fatal(1,"SIMD product lane=%0d",i);
        @(negedge clk);if(done || busy) $fatal(1,"SIMD response did not retire");
        checks++;
    endtask
    initial begin
        for(integer index=0;index<=256;index++) begin
            sample_integer=$rtoi($exp(-real'(index)/16.0)*16777216.0+0.5);
            if(llm_exp_sample(9'(index))!==25'(sample_integer)) $fatal(1,"Softmax LUT index=%0d",index);
            table_checks++;
        end
        for(integer index=0;index<256;index++) begin
            sample_real=-$ln(-$ln((real'(index)+0.5)/256.0))*65536.0;
            sample_integer=$rtoi(sample_real+(sample_real<0 ? -0.5 : 0.5));
            if(llm_gumbel_sample(8'(index))!==24'(sample_integer)) $fatal(1,"Gumbel LUT index=%0d",index);
            table_checks++;
        end
        if(llm_random_next(32'd1)!==32'd270369 || llm_random_next(32'd270369)!==32'd67634689)
            $fatal(1,"Sampler PRNG known values");
        repeat(3) @(negedge clk);rst_n=1;
        for(integer i=0;i<32;i++) begin a[i]=24'sh800000;b[i]=32'sh80000000;end
        check();
        for(integer i=0;i<32;i++) begin a[i]=24'sh7fffff;b[i]=32'sh7fffffff;end
        check();
        for(integer i=0;i<32;i++) begin a[i]=i%2 ? 24'sh800000 : 24'sh7fffff;b[i]=i%2 ? -1 : 1;end
        check();
        repeat(500) begin
            for(integer i=0;i<32;i++) begin a[i]=$urandom;b[i]=$urandom;end
            check();
        end
        for(integer phase=0;phase<7;phase++) begin
            @(negedge clk);start=1;
            @(negedge clk);start=0;
            repeat(phase) @(negedge clk);
            rst_n=0;#1;if(busy || done) $fatal(1,"SIMD reset phase=%0d",phase);
            repeat(2) @(negedge clk);rst_n=1;
            repeat(10) begin @(negedge clk);if(busy || done) $fatal(1,"SIMD canceled response");end
        end
        $display("LLM_MATH_PASS transactions=%0d reset_phases=7 table_checks=%0d reference=S128",checks,table_checks);$finish;
    end
    initial begin #1000000;$fatal(1,"LLM_MATH_TIMEOUT");end
endmodule
