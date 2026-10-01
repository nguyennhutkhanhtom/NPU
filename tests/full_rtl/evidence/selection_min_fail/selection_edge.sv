`timescale 1ns/1ps
module tb_selection_edge;
    logic clk=0,rst_n=0,host_en=0,host_we=0;
    logic [31:0] host_addr=0,host_wdata=0,host_rdata;
    logic host_ready,running,ready,error,overflow_out;
    logic [8:0] pc_debug;
    logic [12:0] instr_debug;
    llm_soc dut(.*);
    always #5 clk=~clk;
    initial begin
        repeat(3) @(negedge clk);rst_n=1;
        force dut.graph=dut.G_HEAD;
        @(negedge clk);
        // All eligible logits can saturate to S32_MIN. Strict comparison
        // must still retain the lowest eligible ID, not the masked token 0.
        force dut.op=dut.H_SELECT;
        force dut.vocabulary_row_q=12'd3;
        force dut.sampled_score_q=-64'sd2147483648;
        @(negedge clk);
        if(dut.best_token_q!==12'd3)
            $fatal(1,"SELECT_MIN_EDGE expected eligible token3 actual=%0d best_score=%0d",dut.best_token_q,dut.best_score_q);
        $display("SELECT_MIN_EDGE_PASS");$finish;
    end
    initial begin #1000;$fatal(1,"Selection edge timeout");end
endmodule
