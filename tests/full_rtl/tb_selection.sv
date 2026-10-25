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
    // The head epilogue is a fixed pipeline: stage 3 rounds the logit and
    // advances the PRNG, stage 4 adds noise and stage 5 selects. op is held in
    // H_STREAM_WAIT so only the forced stage validity drives selection.
    task setup(input integer minimum);
        release dut.graph;release dut.op;release dut.vocabulary_row_q;release dut.sampled_score_q;
        release dut.head_pipe_valid_q;
        @(negedge clk);rst_n=0;repeat(3) @(negedge clk);
        rst_n=1;
        repeat(2) @(negedge clk); // Standard-FF reset boundary releases after two edges.
        dut.min_new_q=8'(minimum);
        force dut.graph=dut.G_HEAD;
        @(negedge clk);
        force dut.op=dut.H_STREAM_WAIT;
    endtask
    task step(input integer token_id,input logic signed [63:0] score,input integer expected);
        force dut.vocabulary_row_q=12'(token_id);
        force dut.sampled_score_q=score;
        force dut.head_pipe_valid_q=6'h20;
        @(negedge clk);
        release dut.head_pipe_valid_q;
        check_best(expected);
    endtask
    task greedy_step(input integer token_id,input logic signed [63:0] product,
                     input logic signed [63:0] rounded,input integer expected);
        logic [31:0] next_random;
        release dut.sampled_score_q;
        force dut.temperature_q=8'd0;
        force dut.vocabulary_row_q=12'(token_id);
        force dut.scalar_product_q=product;
        force dut.head_pipe_valid_q=6'h08;
        #1;release dut.head_pipe_valid_q;
        next_random=dut.random_q^(dut.random_q<<13);
        next_random=next_random^(next_random>>17);
        next_random=next_random^(next_random<<5);
        @(negedge clk);
        if(dut.head_pipe_valid_q!==6'h10 || dut.scalar_round_q!==rounded ||
           dut.noise_product_q!==0 || dut.random_q!==next_random)
            $fatal(1,"Greedy rounding/PRNG/stage mismatch token=%0d",token_id);
        @(negedge clk);
        if(dut.head_pipe_valid_q!==6'h20 || dut.sampled_score_q!==rounded || dut.random_q!==next_random)
            $fatal(1,"Greedy zero-noise score/stage mismatch token=%0d",token_id);
        @(negedge clk);check_best(expected);
        if(dut.head_pipe_valid_q!==0 || dut.random_q!==next_random)
            $fatal(1,"Greedy selection advanced PRNG twice or kept stage validity token=%0d",token_id);
        release dut.scalar_product_q;release dut.temperature_q;
    endtask
    initial begin
        setup(64);check_best(3);
        step(3,-64'sd2147483648,3);
        step(0,64'sd2147483647,3);step(2,64'sd2147483647,3);step(1,64'sd2147483647,3);
        step(3,10,3);step(7,10,3);step(4,11,4);step(8,11,4);
        setup(0);check_best(1);
        step(3,-64'sd2147483648,1);step(1,-64'sd2147483648,1);
        step(0,64'sd2147483647,1);step(2,64'sd2147483647,1);
        setup(64);
        greedy_step(0,64'sd36028797018963968,64'sd2147483648,3);
        greedy_step(1,64'sd36028797018963968,64'sd2147483648,3);
        greedy_step(2,64'sd36028797018963968,64'sd2147483648,3);
        greedy_step(3,64'sd41943040,64'sd2,3); // 2.5 -> even 2
        greedy_step(7,64'sd41943040,64'sd2,3);
        greedy_step(4,64'sd58720256,64'sd4,4); // 3.5 -> even 4
        greedy_step(8,64'sd36028797018963968,64'sd2147483648,8);
        greedy_step(9,64'sd36028797035741184,64'sd2147483649,8); // saturated tie
        setup(0);
        greedy_step(3,-64'sd36028797035741184,-64'sd2147483649,1);
        greedy_step(1,-64'sd36028797018963968,-64'sd2147483648,1);
        // Reset after a greedy row retires must discard both control and PRNG.
        release dut.op;release dut.graph;release dut.vocabulary_row_q;
        rst_n=0;repeat(3) @(negedge clk);rst_n=1;repeat(3) @(negedge clk);
        if(dut.op!==dut.O_IDLE || dut.random_q!==32'd1 || dut.head_pipe_valid_q!==0 || dut.head_busy)
            $fatal(1,"Greedy reset leaked state");
        $display("SELECT_EDGE_PASS checks=%0d minimum_score_ties=2 excluded=5 stable_ties=2",checks);$finish;
    end
    initial begin #3000;$fatal(1,"Selection edge timeout");end
endmodule

