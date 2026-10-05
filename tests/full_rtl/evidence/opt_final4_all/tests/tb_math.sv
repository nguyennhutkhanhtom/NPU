`timescale 1ns/1ps
module tb_llm_math;
    import llm_pkg::*;
    logic clk=0, rst_n=0, start=0, busy, done, in_ready, product_valid, sum_valid;
    logic signed [23:0] a [0:31];
    logic signed [31:0] b [0:31];
    logic signed [55:0] product [0:31];
    logic signed [60:0] sum;
    logic signed [127:0] expected_product [0:31], expected_sum;
    integer checks=0, clocks,table_checks=0,sample_integer;
    real sample_real;
    logic stream_complete, ternary_complete, normalize_complete;
    llm_stream_checker u_stream_check(.complete(stream_complete));
    llm_ternary_checker u_ternary_check(.complete(ternary_complete));
    llm_normalize_checker u_normalize_check(.complete(normalize_complete));
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
        wait(stream_complete && ternary_complete && normalize_complete);
        $display("LLM_MATH_PASS transactions=%0d reset_phases=9 table_checks=%0d bit_checks=%0d reference=S128",checks,table_checks,bit_checks);$finish;
    end
    initial begin #1000000;$fatal(1,"LLM_MATH_TIMEOUT");end
endmodule

// Concurrent independent S128 scoreboards exercise sustained, sparse and cancelled traffic.
module llm_stream_checker(output logic complete = 0);
    logic clk = 0, rst_n = 0, start = 0, busy, done, in_ready, product_valid, sum_valid;
    logic signed [23:0] a [0:31];
    logic signed [31:0] b [0:31];
    wire signed [55:0] product [0:31];
    wire signed [60:0] sum;
    logic signed [127:0] products [0:2047][0:31], sums [0:2047], ref_product, ref_sum;
    integer accepted = 0, product_count = 0, sum_count = 0, checks = 0;
    logic [8:0] expected_valid = 0;
    llm_math #(.STREAMING(1)) dut(.*);
    always #5 clk = ~clk;
    always @(posedge clk) begin
        if (!rst_n) begin accepted=0; product_count=0; sum_count=0; expected_valid=0; end
        else begin
            expected_valid = {expected_valid[7:0], start && in_ready};
            if(start && in_ready) begin
                ref_sum=0;
                for(integer lane=0;lane<32;lane++) begin
                    ref_product=128'(a[lane])*128'(b[lane]);
                    products[accepted][lane]=ref_product; ref_sum+=ref_product;
                end
                sums[accepted]=ref_sum; accepted++;
            end
        end
        #1;
        if(product_valid!==expected_valid[3] || sum_valid!==expected_valid[8])
            $fatal(1,"Streaming SIMD valid/data latency mismatch");
        if(product_valid) begin
            for(integer lane=0;lane<32;lane++)
                if(product[lane]!==products[product_count][lane][55:0])
                    $fatal(1,"Streaming SIMD product transaction=%0d lane=%0d",product_count,lane);
            product_count++; checks++;
        end
        if(sum_valid) begin
            if(sum!==sums[sum_count][60:0]) $fatal(1,"Streaming SIMD sum transaction=%0d",sum_count);
            sum_count++; checks++;
        end
    end
    initial begin
        repeat(3) @(negedge clk);rst_n=1;
        for(integer packet=0;packet<1000;packet++) begin
            @(negedge clk);start=packet<64 || packet%5!=0;
            for(integer lane=0;lane<32;lane++) begin
                a[lane]=packet==0 ? 24'sh800000 : packet==1 ? 24'sh7fffff : 24'($urandom);
                b[lane]=packet==0 ? 32'sh80000000 : packet==1 ? 32'sh7fffffff : 32'($urandom);
            end
        end
        @(negedge clk);start=0;repeat(12) @(negedge clk);
        if(accepted!=product_count || accepted!=sum_count || busy) $fatal(1,"Streaming SIMD lost or duplicated response");
        for(integer phase=0;phase<10;phase++) begin
            @(negedge clk);start=1;
            @(negedge clk);start=0;repeat(phase) @(negedge clk);
            rst_n=0;#1;if(done || sum_valid || product_valid || in_ready) $fatal(1,"Streaming SIMD reset cancellation");
            repeat(2) @(negedge clk);rst_n=1;
            repeat(12) begin @(negedge clk);if(done || sum_valid || product_valid) $fatal(1,"Streaming SIMD stale response");end
        end
        $display("LLM_STREAM_PASS scoreboard_checks=%0d sustained=64 sparse=936 reset_phases=10 reference=S128",checks);
        complete=1;
    end
endmodule

module llm_ternary_checker(output logic complete = 0);
    logic clk=0,rst_n=0,valid_i=0;
    logic signed [23:0] x_i [0:31];
    logic [1:0] w_i [0:31];
    wire valid_o,reserved_o;
    wire signed [29:0] sum_o;
    logic signed [127:0] sums [0:2047], ref_sum;
    logic faults [0:2047];
    logic [3:0] expected_valid=0;
    integer accepted=0,returned=0,checks=0;
    ternary_dot32 dut(.*);
    always #5 clk=~clk;
    always @(posedge clk) begin
        if(!rst_n) begin accepted=0;returned=0;expected_valid=0;end
        else begin
            expected_valid={expected_valid[2:0],valid_i};
            if(valid_i) begin
                ref_sum=0;faults[accepted]=0;
                for(integer lane=0;lane<32;lane++) begin
                    case(w_i[lane])
                        2'b01:ref_sum+=128'(x_i[lane]);
                        2'b11:ref_sum-=128'(x_i[lane]);
                        2'b10:faults[accepted]=1;
                        default:;
                    endcase
                end
                sums[accepted]=ref_sum;accepted++;
            end
        end
        #1;
        if(valid_o!==expected_valid[3]) $fatal(1,"Ternary valid latency");
        if(valid_o) begin
            if(sum_o!==sums[returned][29:0] || reserved_o!==faults[returned])
                $fatal(1,"Ternary exact sum/fault transaction=%0d expected=%h actual=%h",returned,sums[returned],sum_o);
            returned++;checks++;
        end else if(reserved_o) $fatal(1,"Ternary untagged fault");
    end
    initial begin
        repeat(3) @(negedge clk);rst_n=1;
        for(integer packet=0;packet<1000;packet++) begin
            @(negedge clk);valid_i=packet<64 || packet%5!=0;
            for(integer lane=0;lane<32;lane++) begin
                x_i[lane]=packet<4 ? 24'sh800000 : 24'($urandom);
                w_i[lane]=packet<4 ? 2'(packet) : 2'($urandom);
            end
        end
        @(negedge clk);valid_i=0;repeat(6) @(negedge clk);
        if(accepted!=returned) $fatal(1,"Ternary lost/duplicated response");
        for(integer phase=0;phase<4;phase++) begin
            @(negedge clk);valid_i=1;
            @(negedge clk);valid_i=0;repeat(phase) @(negedge clk);
            rst_n=0;#1;if(valid_o || reserved_o) $fatal(1,"Ternary reset cancellation");
            repeat(2) @(negedge clk);rst_n=1;
            repeat(6) begin @(negedge clk);if(valid_o || reserved_o) $fatal(1,"Ternary stale response");end
        end
        $display("LLM_TERNARY_PASS transactions=%0d reserved=checked S24_MIN=checked reset_phases=4 reference=S128",checks);
        complete=1;
    end
endmodule
module llm_normalize_checker(output logic complete=0);
    logic clk=0,rst_n=0,start_i=0,cancel_i=0;
    logic signed [55:0] accumulator_i [0:31];
    logic [31:0] denominator_i;
    wire ready_o,batch_start_o,done_o;
    wire [767:0] vector_o;
    logic signed [127:0] expected [0:31],n,q,r,mag;
    integer clocks,checks=0,cancel_checks=0;
    llm_attention_normalize #(.DIV_LANES(4)) dut(.clk(clk),.rst_n(rst_n),.start_i(start_i),.cancel_i(cancel_i),
        .accumulator_i(accumulator_i),.denominator_i(denominator_i),.ready_o(ready_o),
        .batch_start_o(batch_start_o),.done_o(done_o),.vector_o(vector_o),
        .shared_busy_i(1'b0),.shared_done_i(1'b0),.shared_quotient_i(64'h0),.shared_remainder_i(32'h0),
        .shared_numerator_o(),.shared_denominator_o());
    always #5 clk=~clk;
    task automatic transact(input integer fixture);
        @(negedge clk);
        case(fixture)
            0:denominator_i=1;
            1:denominator_i=2;
            2:denominator_i=3;
            3:denominator_i=65536;
            4:denominator_i=32'hffffffff;
            5:denominator_i=16777216;
            6:denominator_i=16777217;
            7:denominator_i=32'h80000000;
            default:begin denominator_i=$urandom;if(denominator_i==0) denominator_i=1;end
        endcase
        for(integer lane=0;lane<32;lane++) begin
            case(lane%8)
                0:accumulator_i[lane]=56'sh80000000000000;
                1:accumulator_i[lane]=56'sh7fffffffffffff;
                2:accumulator_i[lane]=56'(128'(denominator_i)*3+denominator_i/2);
                3:accumulator_i[lane]=-56'(128'(denominator_i)*2+denominator_i/2);
                4:accumulator_i[lane]=56'(128'(denominator_i)*8388607);
                5:accumulator_i[lane]=-56'(128'(denominator_i)*8388608);
                default:accumulator_i[lane]=56'({$urandom,$urandom});
            endcase
            n=128'(accumulator_i[lane]);mag=n<0 ? -n : n;
            q=mag/128'(denominator_i);r=mag%128'(denominator_i);
            if(2*r>128'(denominator_i) || (2*r==128'(denominator_i) && q[0])) q++;
            expected[lane]=n<0 ? -q : q;
            if(expected[lane]>8388607) expected[lane]=8388607;
            if(expected[lane]<-8388608) expected[lane]=-8388608;
        end
        if(!ready_o) $fatal(1,"Normalizer request before ready");
        start_i=1;@(negedge clk);start_i=0;clocks=0;
        while(!done_o && clocks<700) begin @(negedge clk);clocks++;end
        if(!done_o) $fatal(1,"Normalizer timeout");
        for(integer lane=0;lane<32;lane++) begin
            if(vector_o[lane*24+:24]!==expected[lane][23:0])
                $fatal(1,"Normalizer exact RNE/clamp fixture=%0d lane=%0d expected=%h actual=%h",fixture,lane,expected[lane],vector_o[lane*24+:24]);
            checks++;
        end
        @(negedge clk);if(done_o || !ready_o) $fatal(1,"Normalizer response retirement");
    endtask
    initial begin
        repeat(3) @(negedge clk);rst_n=1;
        for(integer fixture=0;fixture<18;fixture++) transact(fixture);
        for(integer phase=0;phase<6;phase++) begin
            @(negedge clk);start_i=1;@(negedge clk);start_i=0;
            repeat(phase==0 ? 1 : phase==1 ? 2 : phase==2 ? 10 : phase==3 ? 65 : phase==4 ? 68 : 70) @(negedge clk);
            rst_n=0;#1;if(done_o || batch_start_o) $fatal(1,"Normalizer reset cancellation");
            repeat(2) @(negedge clk);rst_n=1;
            repeat(72) begin @(negedge clk);if(done_o || batch_start_o) $fatal(1,"Normalizer stale reset response");end
            cancel_checks++;
        end
        for(integer phase=0;phase<3;phase++) begin
            @(negedge clk);start_i=1;@(negedge clk);start_i=0;repeat(3+phase*20) @(negedge clk);
            cancel_i=1;@(negedge clk);cancel_i=0;
            while(!ready_o) begin @(negedge clk);if(done_o) $fatal(1,"Normalizer stale cancelled response");end
            transact(phase);cancel_checks++;
        end
        $display("LLM_NORMALIZE_PASS lane_checks=%0d cancellation_phases=%0d RNE_ties=checked S56_extremes=checked reference=S128",checks,cancel_checks);
        complete=1;
    end
endmodule

