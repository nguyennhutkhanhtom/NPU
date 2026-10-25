`timescale 1ns/1ps
// Ordered vocabulary rows against an independent wide-integer reference. The
// engine shares one in-order fixed-latency read stream for packed scale words
// and int8 weight words, and issues into the real streaming llm_math.
module tb_llm_head_stream;
    logic clk=0, rst_n=0, start=0, cancel=0;
    always #5 clk=~clk;
    logic busy, req, parameter_valid=0, capture, issue, result_valid;
    logic [14:0] address;
    logic [255:0] parameter_data=0;
    logic [1:0] input_chunk;
    logic math_busy, math_done, math_in_ready, product_valid, sum_valid;
    logic signed [55:0] product [0:31];
    logic signed [60:0] sum;
    logic signed [23:0] math_a [0:31];
    logic signed [31:0] math_b [0:31];
    logic signed [38:0] result;
    logic [23:0] coefficient;
    integer latency=5, cycle=0, pending_read=0, pending_write=0;
    integer pending_address[0:32767], pending_due[0:32767];
    integer weight_reads=0, scale_reads=0, issues=0, accepted=0, started=0;
    integer inflight_max=0, inflight_sum=0, credit_stalls=0, port_idle=0, first_cycle=0, last_cycle=0;
    bit measuring=0, cancelled=0;
    llm_head_engine #(.SCALE_BASE(23040)) dut(.clk(clk), .rst_n(rst_n), .start_i(start), .cancel_i(cancel),
        .busy_o(busy), .parameter_req_o(req), .parameter_address_o(address),
        .parameter_valid_i(parameter_valid), .parameter_data_i(parameter_data),
        .operand_capture_o(capture), .math_issue_o(issue), .input_chunk_o(input_chunk),
        .sum_valid_i(sum_valid), .sum_i(sum), .result_valid_o(result_valid),
        .accumulator_o(result), .coefficient_o(coefficient));
    llm_math #(.STREAMING(1)) u_math(.clk(clk), .rst_n(rst_n), .start(issue), .a(math_a), .b(math_b),
        .busy(math_busy), .done(math_done), .in_ready(math_in_ready), .product_valid(product_valid),
        .sum_valid(sum_valid), .product(product), .sum(sum));
    function automatic integer input_value(input integer i);
        case(i%7)
            0:return -8388608;
            1:return 8388607;
            default:return (i*7919)%200003-100001;
        endcase
    endfunction
    function automatic integer weight(input integer row, i);
        return row%61==0 ? (i%2 ? 127 : -128) : ((row*29+i*31+i/5)%256)-128;
    endfunction
    function automatic logic [23:0] row_scale(input integer row);
        if(row%97==0) return 24'hffffff;
        if(row%89==0) return 24'h000000;
        return 24'(row*40503+12345);
    endfunction
    // Slot bits [31:24] are not part of the U24 scale.
    function automatic logic [255:0] word_data(input integer addr);
        logic [255:0] data;
        data=0;
        if(addr>=23040) begin
            for(integer slot=0;slot<8;slot++) data[slot*32+:32]={8'ha5,row_scale((addr-23040)*8+slot)};
        end else begin
            for(integer lane=0;lane<32;lane++) data[lane*8+:8]=8'(weight(addr/4,(addr%4)*32+lane));
        end
        return data;
    endfunction
    function automatic logic signed [127:0] reference_dot(input integer row);
        reference_dot=0;
        for(integer i=0;i<128;i++) reference_dot+=128'(input_value(i))*128'(weight(row,i));
    endfunction
    // Parent operand capture: hidden chunk on A, sign-extended int8 weights on B.
    for(genvar lane=0;lane<32;lane++) begin : g_operand
        always @(posedge clk)
            if(rst_n && capture) begin
                math_a[lane]<=24'(input_value(int'(input_chunk)*32+lane));
                math_b[lane]<=32'($signed(parameter_data[lane*8+:8]));
            end
    end
    always @(posedge clk) begin
        if(!rst_n) begin
            cycle=0; pending_read=0; pending_write=0;
        end else begin
            cycle++;
            if(req) begin
                if(dut.request_scale_q) begin
                    if(address!==15'(23040+started/8)) $fatal(1,"Scale request order row=%0d address=%0d",started,address);
                    if(measuring) scale_reads++;
                end else begin
                    if(address!==15'(dut.request_row_q*4+dut.request_chunk_q) || dut.request_row_q!=started-(dut.request_chunk_q!=0))
                        $fatal(1,"Weight request order row=%0d address=%0d",started,address);
                    if(measuring) weight_reads++;
                    if(dut.request_chunk_q==0) started++;
                end
                pending_address[pending_write]=int'(address);
                pending_due[pending_write]=cycle+latency-1;
                pending_write++;
            end
            if(capture && (cancel || cancelled || dut.state!=2'd1)) $fatal(1,"Operand capture outside a live stream");
            if(cancel) cancelled=1;
            else if(cancelled && result_valid) $fatal(1,"Row retired after cancellation");
            if(measuring) begin
                if(issue) issues++;
                if(dut.state==2'd1 && !dut.request_row_q[12] && !req) begin
                    port_idle++;
                    if(dut.reads_pending_q==8) credit_stalls++;
                end
                if(dut.reads_pending_q>8 || dut.sums_pending_q>10) $fatal(1,"Read or SIMD outstanding bound exceeded");
                if(started-accepted>inflight_max) inflight_max=started-accepted;
                if(busy) inflight_sum+=started-accepted;
                if(result_valid && !cancelled) begin
                    automatic logic signed [127:0] expected=reference_dot(accepted);
                    if(result!==expected[38:0] || coefficient!==row_scale(accepted))
                        $fatal(1,"Row result row=%0d expected=%0d/%h actual=%0d/%h",accepted,expected,row_scale(accepted),result,coefficient);
                    accepted++; last_cycle=cycle;
                end
            end
        end
    end
    always @(negedge clk) begin
        parameter_valid=0;
        if(rst_n && pending_read<pending_write && pending_due[pending_read]<=cycle) begin
            parameter_valid=1; parameter_data=word_data(pending_address[pending_read]); pending_read++;
        end
    end
    task automatic reset_fixture;
        @(negedge clk); rst_n=0; start=0; cancel=0; measuring=0;
        repeat(3) @(negedge clk);
        rst_n=1; @(negedge clk);
    endtask
    task automatic clear_counts;
        if(pending_read!=pending_write) $fatal(1,"Counts cleared with reads in flight");
        pending_read=0; pending_write=0;
        weight_reads=0; scale_reads=0; issues=0; accepted=0; started=0; cancelled=0;
        inflight_max=0; inflight_sum=0; credit_stalls=0; port_idle=0;
    endtask
    // One complete pass from an idle engine; the stream must not consume any
    // response, sum or scale slot left by an earlier cancelled pass.
    task automatic run_pass(input integer memory_latency, input bit report);
        integer waits;
        clear_counts(); latency=memory_latency; measuring=1;
        start=1; first_cycle=cycle+1; @(negedge clk); start=0;
        waits=0;
        while((busy || accepted<4096) && waits<200000) begin @(negedge clk); waits++; end
        if(waits>=200000 || pending_read!=pending_write || math_busy) $fatal(1,"Head stream drain timeout");
        if(accepted!=4096 || weight_reads!=16384 || scale_reads!=512 || issues!=16384 ||
           dut.reads_pending_q!=0 || dut.sums_pending_q!=0)
            $fatal(1,"Head conservation rows=%0d weights=%0d scales=%0d issues=%0d",accepted,weight_reads,scale_reads,issues);
        // Eight read credits cover the five-edge parameter SRAM response.
        if(port_idle!=credit_stalls || (memory_latency>7)!=(credit_stalls!=0))
            $fatal(1,"Read-credit stall classification latency=%0d idle=%0d credit=%0d",memory_latency,port_idle,credit_stalls);
        if(report) $display("HEAD_STREAM_METRIC latency=%0d rows=4096 cycles=%0d weight_reads=%0d scale_reads=%0d port_util_pct=%0.2f simd_issues=%0d simd_util_pct=%0.2f rows_in_flight_max=%0d rows_in_flight_avg=%0.2f port_idle=%0d read_credit_stalls=%0d",
            memory_latency,last_cycle-first_cycle+1,weight_reads,scale_reads,100.0*(weight_reads+scale_reads)/(last_cycle-first_cycle+1),
            issues,100.0*issues/(last_cycle-first_cycle+1),inflight_max,real'(inflight_sum)/(last_cycle-first_cycle+1),port_idle,credit_stalls);
        measuring=0;
    endtask
    task automatic cancel_pass(input integer phase);
        integer waits;
        clear_counts(); latency=5; measuring=1;
        start=1; @(negedge clk); start=0;
        case(phase)
            0: wait(req);
            1: wait(dut.scale_capture);
            2: wait(capture);
            3: wait(issue);
            4: wait(result_valid);
            default: wait(accepted==1000);
        endcase
        @(negedge clk); cancel=1; @(negedge clk); cancel=0;
        waits=0;
        while(busy && waits<100) begin @(negedge clk); waits++; end
        if(busy || waits>=100 || req || capture || issue || result_valid || pending_read!=pending_write ||
           math_busy || dut.reads_pending_q!=0 || dut.sums_pending_q!=0)
            $fatal(1,"Cancel failed to drain phase=%0d",phase);
        measuring=0; repeat(3) @(negedge clk);
        if(parameter_valid || req) $fatal(1,"Stale parameter traffic after drain phase=%0d",phase);
    endtask
    initial begin
        reset_fixture();
        run_pass(5,1);
        run_pass(1,1);
        run_pass(40,1);
        for(integer phase=0;phase<6;phase++) begin
            cancel_pass(phase);
            run_pass(5,0);
        end
        for(integer phase=0;phase<4;phase++) begin
            clear_counts(); latency=5;
            start=1; @(negedge clk); start=0;
            if(phase==0) wait(req);
            if(phase==1) wait(capture);
            if(phase==2) wait(result_valid);
            if(phase==3) wait(started==2048);
            @(negedge clk); rst_n=0; #1;
            if(busy || req || capture || issue || result_valid) $fatal(1,"Reset leaked work phase=%0d",phase);
            repeat(3) @(negedge clk); rst_n=1; @(negedge clk);
            run_pass(5,0);
        end
        $display("LLM_HEAD_STREAM_PASS exact_rows=4096 latency=1_5_40 read_credit=checked cancel_drain=6 reset=4");
        $finish;
    end
    initial begin #50000000; $fatal(1,"Head stream watchdog"); end
endmodule
