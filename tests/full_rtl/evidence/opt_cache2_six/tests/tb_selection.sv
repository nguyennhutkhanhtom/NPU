`timescale 1ns/1ps
module tb_llm_selection;
    logic clk=0,rst_n=0,host_en=0,host_we=0;
    logic [31:0] host_addr=0,host_wdata=0,host_rdata;
    logic host_ready,running,ready,error,overflow_out;
    logic [8:0] pc_debug;
    logic [12:0] instr_debug;
    llm_soc dut(.*);
    always #5 clk=~clk;
    integer checks=0;
    task check_best(input integer expected);
        if(dut.best_token_q!==12'(expected))
            $fatal(1,"SELECT_EDGE expected eligible token=%0d actual=%0d score=%0d",expected,dut.best_token_q,dut.best_score_q);
        checks++;
    endtask
    task setup(input integer minimum);
        release dut.graph;release dut.op;release dut.vocabulary_row_q;release dut.sampled_score_q;
        @(negedge clk);rst_n=0;repeat(3) @(negedge clk);
        rst_n=1;
        repeat(2) @(negedge clk); // Standard-FF reset boundary releases after two edges.
        dut.min_new_q=8'(minimum);
        force dut.graph=dut.G_HEAD;
        @(negedge clk);
        force dut.op=dut.H_SELECT;
    endtask
    task step(input integer token_id,input logic signed [63:0] score,input integer expected);
        force dut.vocabulary_row_q=12'(token_id);
        force dut.sampled_score_q=score;
        @(negedge clk);
        check_best(expected);
    endtask
    initial begin
        setup(64);check_best(3);
        step(3,-64'sd2147483648,3);
        step(0,64'sd2147483647,3);step(2,64'sd2147483647,3);step(1,64'sd2147483647,3);
        step(3,10,3);step(7,10,3);step(4,11,4);step(8,11,4);
        setup(0);check_best(1);
        step(3,-64'sd2147483648,1);step(1,-64'sd2147483648,1);
        step(0,64'sd2147483647,1);step(2,64'sd2147483647,1);
        $display("SELECT_EDGE_PASS checks=%0d minimum_score_ties=2 excluded=5 stable_ties=2",checks);$finish;
    end
    initial begin #1000;$fatal(1,"Selection edge timeout");end
endmodule

