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
    logic [8:0] table_index;
    wire [24:0] exp_value;
    wire signed [23:0] gumbel_value;
    llm_exp_sample u_exp(.index(table_index), .value(exp_value));
    llm_gumbel_sample u_gumbel(.index(table_index[7:0]), .value(gumbel_value));
    logic [3:0] small_a, small_b;
    wire [7:0] small_product [0:3];
    wire [4:0] small_truncated;
    wire one_product;
    integer bit_checks=0;
    logic signed [127:0] ref_a, ref_b, ref_product;
    for (genvar mode=0; mode<4; mode++) begin : g_small
        logic_mul #(.A_W(4),.B_W(4),.OUT_W(8),.SIGNED_A(mode & 1),.SIGNED_B((mode >> 1) & 1)) u_mul
            (.a(small_a),.b(small_b),.product(small_product[mode]));
    end
    logic_mul #(.A_W(4),.B_W(4),.OUT_W(5),.SIGNED_A(1),.SIGNED_B(1)) u_truncated
        (.a(small_a),.b(small_b),.product(small_truncated));
    logic_mul #(.A_W(1),.B_W(1),.OUT_W(1),.SIGNED_A(1),.SIGNED_B(1)) u_one
        (.a(small_a[0]),.b(small_b[0]),.product(one_product));
    always #5 clk=~clk;
    task automatic check;
        expected_sum=0;
        for(integer i=0;i<32;i++) begin
            expected_product[i]=128'(a[i])*128'(b[i]);
            expected_sum+=expected_product[i];
        end
        @(negedge clk);start=1;
        @(negedge clk);start=0;clocks=0;
        while(!done && clocks<12) begin
            for(integer i=0;i<32;i++) begin a[i]=$urandom;b[i]=$urandom;end
            start=clocks==1; // Busy requests must not replace this transaction.
            @(negedge clk);start=0;clocks++;
        end
        if(!done || clocks!=9) $fatal(1,"SIMD latency clocks=%0d",clocks);
        if(sum!==expected_sum[60:0]) $fatal(1,"SIMD sum expected=%h actual=%h",expected_sum,sum);
        for(integer i=0;i<32;i++)
            if(product[i]!==expected_product[i][55:0]) $fatal(1,"SIMD product lane=%0d",i);
        @(negedge clk);if(done || busy) $fatal(1,"SIMD response did not retire");
        checks++;
    endtask
    initial begin
        // Exhaust every bit pattern and all signed/unsigned interpretations.
        // Independent arithmetic stays in the testbench, never in RTL.
        for(integer av=0;av<16;av++) for(integer bv=0;bv<16;bv++) begin
            small_a=4'(av);small_b=4'(bv);#1;
            for(integer mode=0;mode<4;mode++) begin
                ref_a=(mode & 1) ? 128'($signed(small_a)) : 128'(av);
                ref_b=(mode & 2) ? 128'($signed(small_b)) : 128'(bv);
                ref_product=ref_a*ref_b;
                if(small_product[mode]!==ref_product[7:0]) $fatal(1,"Bit multiplier mode=%0d a=%0d b=%0d",mode,av,bv);
                bit_checks++;
            end
            ref_product=128'($signed(small_a))*128'($signed(small_b));
            if(small_truncated!==ref_product[4:0]) $fatal(1,"Bit multiplier truncation");
            if(one_product!==(small_a[0] & small_b[0])) $fatal(1,"Bit multiplier one-bit signed");
            bit_checks+=2;
        end
        for(integer index=0;index<=256;index++) begin
            sample_integer=$rtoi($exp(-real'(index)/16.0)*16777216.0+0.5);
            table_index=9'(index); #1;
            if(exp_value!==25'(sample_integer)) $fatal(1,"Softmax LUT index=%0d",index);
            table_checks++;
        end
        for(integer index=0;index<256;index++) begin
            sample_real=-$ln(-$ln((real'(index)+0.5)/256.0))*65536.0;
            sample_integer=$rtoi(sample_real+(sample_real<0 ? -0.5 : 0.5));
            table_index=9'(index); #1;
            if(gumbel_value!==24'(sample_integer)) $fatal(1,"Gumbel LUT index=%0d",index);
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
        for(integer phase=0;phase<9;phase++) begin
            @(negedge clk);start=1;
            @(negedge clk);start=0;
            repeat(phase) @(negedge clk);
            rst_n=0;#1;if(busy || done) $fatal(1,"SIMD reset phase=%0d",phase);
            repeat(2) @(negedge clk);rst_n=1;
            repeat(10) begin @(negedge clk);if(busy || done) $fatal(1,"SIMD canceled response");end
        end
        $display("LLM_MATH_PASS transactions=%0d reset_phases=9 table_checks=%0d bit_checks=%0d reference=S128",checks,table_checks,bit_checks);$finish;
    end
    initial begin #1000000;$fatal(1,"LLM_MATH_TIMEOUT");end
endmodule
