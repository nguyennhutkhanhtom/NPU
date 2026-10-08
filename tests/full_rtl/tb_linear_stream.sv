`timescale 1ns/1ps
// Ordered rows against an independent wide-integer reference. The baseline
// define runs this same operand/memory fixture with the former one-row API.
module tb_llm_linear_stream;
    logic clk=0, rst_n=0, start=0, cancel=0;
    always #5 clk=~clk;
    logic [3:0] chunks=4;
    logic [9:0] rows=128;
    logic ready, busy, done, fault, req, parameter_valid=0, dot_issue;
    logic [14:0] address, base=100;
    logic [255:0] parameter_data=0;
    logic [3:0] input_chunk;
    logic signed [23:0] x[0:31];
    logic signed [38:0] result;
    logic result_valid, result_fault, result_ready=1;
    integer latency=5, cycle=0, reads=0, issues=0, accepted=0, first_row_cycle=-1, last_row_cycle=-1;
    integer row_intervals=0, interval_total=0, interval_min=100000, interval_max=0;
    integer fault_row=-1, fault_chunk=0, pending_read=0, pending_write=0;
    integer pending_address[0:2047], pending_due[0:2047];
    bit measuring=0, saw_done=0, saw_fault=0, stall_results=0;
    logic held=0;
    logic signed [38:0] held_result;
    logic held_fault;
`ifdef PHASE1A_BASELINE
    assign result_valid=done;
    assign result_fault=fault;
    llm_linear_engine dut(.clk(clk), .rst_n(rst_n), .start_i(start), .cancel_i(cancel),
        .weight_base_i(base), .chunks_i(chunks), .ready_o(ready), .busy_o(busy),
        .done_o(done), .fault_o(fault), .parameter_req_o(req), .parameter_address_o(address),
        .parameter_valid_i(parameter_valid), .parameter_data_i(parameter_data),
        .input_chunk_o(input_chunk), .x_i(x), .dot_issue_o(dot_issue), .accumulator_o(result));
`else
    llm_linear_engine dut(.clk(clk), .rst_n(rst_n), .start_i(start), .cancel_i(cancel),
        .weight_base_i(base), .chunks_i(chunks), .rows_i(rows), .result_ready_i(result_ready),
        .result_valid_o(result_valid), .result_fault_o(result_fault),
        .ready_o(ready), .busy_o(busy), .done_o(done), .fault_o(fault),
        .parameter_req_o(req), .parameter_address_o(address),
        .parameter_valid_i(parameter_valid), .parameter_data_i(parameter_data),
        .input_chunk_o(input_chunk), .x_i(x), .dot_issue_o(dot_issue), .accumulator_o(result));
`endif
    function automatic integer operand(input integer i);
        case(i%7)
            0:return -8388608;
            1:return 8388607;
            default:return (i*7919)%200003-100001;
        endcase
    endfunction
    function automatic integer weight(input integer row, i);
        return ((row*17+i*13+i/9)%3)-1;
    endfunction
    function automatic logic [255:0] word_data(input integer addr);
        integer row, word_id, i;
        logic [255:0] data;
        row=(addr-100)/(int'(chunks)/4); word_id=(addr-100)%(int'(chunks)/4);
        data=0;
        for(i=0;i<128;i++) begin
            case(weight(row,word_id*128+i))
                -1:data[i*2+:2]=2'b11;
                1:data[i*2+:2]=2'b01;
                default:data[i*2+:2]=0;
            endcase
            if(row==fault_row && word_id*4+i/32==fault_chunk && i%32==31)
                data[i*2+:2]=2'b10;
        end
        return data;
    endfunction
    for(genvar lane=0;lane<32;lane++) begin : g_x
        always_comb x[lane]=24'(operand(int'(input_chunk)*32+lane));
    end
    always @(posedge clk) begin
        if(!rst_n) begin
            cycle=0; pending_read=0; pending_write=0; held=0;
        end else begin
            cycle++;
            if(req) begin
                pending_address[pending_write]=int'(address);
                pending_due[pending_write]=cycle+latency-1;
                pending_write++; if(measuring) reads++;
            end
            if(measuring) begin
                if(dot_issue) issues++;
                if(dut.operand_capture && input_chunk==0) begin
                    if(first_row_cycle<0) first_row_cycle=cycle;
                    if(last_row_cycle>=0) begin
                        row_intervals++; interval_total+=cycle-last_row_cycle;
                        if(cycle-last_row_cycle<interval_min) interval_min=cycle-last_row_cycle;
                        if(cycle-last_row_cycle>interval_max) interval_max=cycle-last_row_cycle;
                    end
                    last_row_cycle=cycle;
                end
                if(req && address!==15'(100+reads-1)) $fatal(1,"Parameter request order");
                if((int'(dut.request_q)-int'(dut.words_consumed))>2) $fatal(1,"Word credits");
`ifndef PHASE1A_BASELINE
                if(dut.result_count_q>4 || (dut.started_rows_q-dut.consumed_rows_q)>4)
                    $fatal(1,"Row credits");
                if(held && !cancel && (!result_valid || result!==held_result || result_fault!==held_fault))
                    $fatal(1,"Result changed under backpressure");
                held=result_valid && !result_ready && !cancel;
                held_result=result; held_fault=result_fault;
`endif
                if(done) saw_done=1;
                if(result_valid && result_ready && !cancel) begin
                    if(result_fault) begin
                        if(accepted!=fault_row) $fatal(1,"Fault order row=%0d expected=%0d",accepted,fault_row);
                        saw_fault=1;
                    end else begin
                        automatic logic signed [127:0] reference_sum=0;
                        for(integer i=0;i<int'(chunks)*32;i++)
                            reference_sum+=128'(operand(i))*128'(weight(accepted,i));
                        if(result!==reference_sum[38:0])
                            $fatal(1,"Row sum row=%0d expected=%0d actual=%0d",accepted,reference_sum,result);
                        if(saw_fault) $fatal(1,"Result after fault");
                        accepted++;
                    end
                end
            end
        end
    end
    always @(negedge clk) begin
        parameter_valid=0;
        if(rst_n && pending_read<pending_write && pending_due[pending_read]<=cycle) begin
            parameter_valid=1; parameter_data=word_data(pending_address[pending_read]); pending_read++;
        end
`ifndef PHASE1A_BASELINE
        result_ready=!(stall_results && (cycle%53)<23);
`endif
    end
    task automatic reset_fixture;
        @(negedge clk); rst_n=0; start=0; cancel=0; measuring=0;
        repeat(3) @(negedge clk);
        reads=0; issues=0; accepted=0; first_row_cycle=-1; last_row_cycle=-1;
        row_intervals=0; interval_total=0; interval_min=100000; interval_max=0;
        saw_done=0; saw_fault=0; base=100; result_ready=1;
        rst_n=1;
    endtask
    task automatic run_matrix(input integer k, m, memory_latency, bad_row, bad_chunk, input bit stalls);
        integer waits;
        reset_fixture(); chunks=4'(k/32); rows=10'(m); latency=memory_latency;
        fault_row=bad_row; fault_chunk=bad_chunk; stall_results=stalls;
        measuring=1; @(negedge clk); start=1; @(negedge clk); start=0;
        waits=0;
        while((busy || !saw_done || (bad_row<0 && accepted<m) || (bad_row>=0 && !saw_fault)) && waits<30000) begin
            @(negedge clk); waits++;
`ifdef PHASE1A_BASELINE
            if(!busy && !done && accepted<m && !saw_fault) begin
                base=15'(100+accepted*(k/128)); start=1;
                @(negedge clk); start=0;
            end
`endif
        end
        if(waits>=30000 || pending_read!=pending_write) $fatal(1,"Stream drain timeout");
        if(bad_row<0 && (accepted!=m || reads!=m*(k/128) || issues!=m*(k/32)))
            $fatal(1,"Matrix conservation rows=%0d reads=%0d issues=%0d",accepted,reads,issues);
        if(bad_row>=0 && (!saw_fault || !fault || accepted!=bad_row)) $fatal(1,"Missing ordered fault");
        if(bad_row<0 && !stalls) $display("LINEAR_STREAM_METRIC k=%0d rows=%0d latency=%0d cycles=%0d dot_issues=%0d parameter_reads=%0d row_ii_sum=%0d row_ii_count=%0d row_ii_min=%0d row_ii_max=%0d",
            k,m,memory_latency,cycle,issues,reads,interval_total,row_intervals,interval_min,interval_max);
        measuring=0;
    endtask
    initial begin
        run_matrix(128,128,5,-1,0,0);
        run_matrix(384,128,5,-1,0,0);
        run_matrix(128,384,5,-1,0,0);
        run_matrix(128,128,1,-1,0,1);
        run_matrix(384,128,9,-1,0,1);
        run_matrix(128,128,5,0,3,0);
        run_matrix(128,128,5,1,0,1);
        run_matrix(384,128,5,33,11,0);
`ifndef PHASE1A_BASELINE
        for(integer phase=0;phase<4;phase++) begin
            reset_fixture(); chunks=4; rows=128; fault_row=-1; latency=5; stall_results=0;
            @(negedge clk); start=1; @(negedge clk); start=0;
            if(phase==0) wait(req);
            if(phase==1) wait(dot_issue);
            if(phase==2) begin force result_ready=0; wait(dut.result_count_q==4); end
            if(phase==3) begin wait(dot_issue); @(negedge clk); cancel=1;
                wait(done); @(negedge clk);
                if(busy || req || result_valid || dut.launch_q || dut.retired_q!=dut.issue_q ||
                   dut.response_q!=dut.request_q) $fatal(1,"Cancel failed to drain");
            end
            @(negedge clk); rst_n=0; #1;
            if(busy || result_valid || req || dut.launch_q) $fatal(1,"Reset leaked work");
            if(phase==2) release result_ready;
        end
`endif
        $display("LLM_LINEAR_STREAM_PASS exact_rows=128_384 fifo_backpressure=checked fault_order=checked drain_reset_cancel=checked");
        $finish;
    end
    initial begin #5000000; $fatal(1,"Linear stream watchdog"); end
endmodule
