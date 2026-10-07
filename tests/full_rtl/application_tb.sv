`timescale 1ns/1ps
// Host supplies checkpoint/config/prompt only. Continuation is computed on RTL.
module tb_full_rtl_application;
    logic clk=0,rst_n=0,host_en=0,host_we=0;
    logic [31:0] host_addr=0,host_wdata=0,host_rdata;
    logic host_ready,running,ready,error,overflow_out;
    logic [8:0] pc_debug;
    logic [12:0] instr_debug;
    llm_soc dut(.*);
    always #5 clk=~clk;
    `include "config.svh"
    logic [255:0] parameters[0:24575];
    logic [11:0] prompt[0:PROMPT_COUNT-1],expected[0:EXPECTED_COUNT-1];
    logic [31:0] response;
    integer fd,clocks=0,commands=0;
    integer checked_tokens=0;
    // Read-only verification: expected IDs never drive a DUT port or state.
    // Observe completed token writes so a mismatch stops the long run early;
    // the final host reads below independently verify the public interface.
    always @(negedge clk) begin
        if(!rst_n) checked_tokens=0;
        else if(dut.core_rst_n && dut.generated_q>checked_tokens) begin
            if(dut.generated_q!=checked_tokens+1 || checked_tokens>=EXPECTED_COUNT)
                $fatal(1,"Unexpected generated-token count actual=%0d checked=%0d expected=%0d",dut.generated_q,checked_tokens,EXPECTED_COUNT);
            if(dut.output_memory[checked_tokens]!==expected[checked_tokens])
                $fatal(1,"Early full graph token mismatch index=%0d expected=%0d actual=%0d",checked_tokens,expected[checked_tokens],dut.output_memory[checked_tokens]);
            $display("FULL_RTL_TOKEN_VERIFIED index=%0d token=%0d",checked_tokens,dut.output_memory[checked_tokens]);
            checked_tokens++;
        end
    end
    task automatic transaction(input bit write,input logic [31:0] address,data,
                               output logic [31:0] result);
        integer waits;
        @(negedge clk);host_en=1;host_we=write;host_addr=address;host_wdata=data;waits=0;
        while(!host_ready && waits<16) begin @(negedge clk);waits++;end
        if(!host_ready) $fatal(1,"Host timeout addr=%h",address);
        result=host_rdata;commands++;
        @(negedge clk);host_en=0;host_we=0;
        @(negedge clk);if(host_ready) $fatal(1,"Host response did not retire");
    endtask
    initial begin
        $readmemh("tests/full_rtl/build/parameter.mem",parameters);
        $readmemh("tests/full_rtl/build/prompt.mem",prompt);
        $readmemh("tests/full_rtl/build/expected.mem",expected);
        repeat(3) @(negedge clk);rst_n=1;
        $display("FULL_RTL_LOAD_START rows=24576 time=%0t",$time);
        for(integer row=0;row<24576;row++) begin
            for(integer lane=0;lane<8;lane++)
                transaction(1,32'(row*32+lane*4),parameters[row][lane*32+:32],response);
            if((row+1)%1024==0)
                $display("FULL_RTL_LOAD_PROGRESS rows=%0d/24576 host_commands=%0d time=%0t",row+1,commands,$time);
        end
        $display("FULL_RTL_LOAD_COMPLETE host_commands=%0d time=%0t",commands,$time);
        for(integer token=0;token<PROMPT_COUNT;token++)
            transaction(1,32'h00100000+token*4,{20'h0,prompt[token]},response);
        transaction(1,32'h00400004,PROMPT_COUNT,response);
        transaction(1,32'h00400008,MAX_NEW,response);
        transaction(1,32'h00400010,TEMPERATURE,response);
        transaction(1,32'h00400014,SEED,response);
        transaction(1,32'h00400018,MIN_NEW,response);
        transaction(1,32'h0040000c,1,response);
        if(!running) $fatal(1,"Autonomous graph did not start");
        $display("FULL_RTL_GRAPH_START prompt=%0d new_tokens=%0d time=%0t",PROMPT_COUNT,MAX_NEW,$time);
        while(running && clocks<150000000) begin
            @(negedge clk);clocks++;
            if(clocks%100000==0)
                $display("FULL_RTL_PROGRESS clocks=%0d position=%0d generated=%0d phase=%0d",clocks,pc_debug,dut.generated_q,dut.graph);
        end
        if(running || error) $fatal(1,"Autonomous graph timeout/error clocks=%0d",clocks);
        transaction(0,32'h00400000,0,response);
        if(response[11:4]!==8'(EXPECTED_COUNT)) $fatal(1,"Continuation length expected=%0d actual=%0d",EXPECTED_COUNT,response[11:4]);
        fd=$fopen("tests/full_rtl/build/rtl_tokens.txt","w");
        for(integer token=0;token<EXPECTED_COUNT;token++) begin
            transaction(0,32'h00200000+token*4,0,response);
            $fdisplay(fd,"%0d",response[11:0]);
            if(response[11:0]!==expected[token])
                $fatal(1,"Full graph token mismatch index=%0d expected=%0d actual=%0d",token,expected[token],response[11:0]);
        end
        $fclose(fd);
        if(checked_tokens!=EXPECTED_COUNT) $fatal(1,"Completed-token verification count=%0d expected=%0d",checked_tokens,EXPECTED_COUNT);
        $display("FULL_RTL_APPLICATION_PASS tokens=%0d clocks=%0d host_commands=%0d overflow=%b",EXPECTED_COUNT,clocks,commands,overflow_out);
        $finish;
    end
    initial begin #2000000000;$fatal(1,"FULL_RTL_APPLICATION_TIMEOUT");end
endmodule
