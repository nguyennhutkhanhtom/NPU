`timescale 1ns/1ps
module tb_llm_protocol;
    logic clk=0,rst_n=0,host_en=0,host_we=0;
    logic [31:0] host_addr=0,host_wdata=0,host_rdata;
    logic host_ready,running,ready,error,overflow_out;
    logic [8:0] pc_debug;
    logic [12:0] instr_debug;
    logic [31:0] result;
    integer checks=0;
    llm_soc dut(.*);
    always #5 clk=~clk;
    task automatic transaction(input bit write,input logic [31:0] address,data,
                               output logic [31:0] response);
        integer waits;
        @(negedge clk);host_en=1;host_we=write;host_addr=address;host_wdata=data;waits=0;
        while(!host_ready && waits<8) begin @(negedge clk);waits++;end
        if(!host_ready) $fatal(1,"LLM host timeout addr=%h",address);
        response=host_rdata;checks++;
        repeat(2) begin @(negedge clk);if(!host_ready || host_rdata!==response) $fatal(1,"LLM host held response");end
        host_en=0;host_we=0;
        @(negedge clk);if(host_ready) $fatal(1,"LLM host release");
    endtask
    task automatic check_read(input logic [31:0] address,expected);
        transaction(0,address,0,result);
        if(result!==expected) $fatal(1,"LLM host read addr=%h expected=%h actual=%h",address,expected,result);
    endtask
    initial begin
        repeat(3) @(negedge clk);rst_n=1;
        transaction(1,0,32'h12345678,result);check_read(0,32'h12345678);
        transaction(1,32'h000bfffc,32'hcafef00d,result);check_read(32'h000bfffc,32'hcafef00d);
        transaction(1,32'h000c0000,32'habcdef01,result);check_read(32'h000c0000,0);check_read(0,32'h12345678);
        transaction(1,1,32'hbadcafe0,result);check_read(1,0);check_read(0,32'h12345678);
        // Dropping enable before the execution edge cancels a pending write.
        @(negedge clk);host_en=1;host_we=1;host_addr=0;host_wdata=32'hbad00000;
        @(negedge clk);host_en=0;host_we=0;
        @(negedge clk);check_read(0,32'h12345678);
        for(integer phase=1;phase<=4;phase++) begin
            @(negedge clk);host_en=1;host_we=0;host_addr=0;
            repeat(phase) @(negedge clk);host_en=0;
            repeat(3) begin @(negedge clk);if(host_ready) $fatal(1,"Canceled host response escaped");end
            check_read(32'h000bfffc,32'hcafef00d);
        end
        force dut.graph=dut.G_DONE;
        repeat(3) @(negedge clk);
        transaction(1,0,32'hbad00001,result);check_read(0,0);check_read(32'h00400000,1);
        release dut.graph;
        repeat(3) @(negedge clk);check_read(0,32'h12345678);
        // Invalid prompt count must fail without accessing an uninitialized graph.
        transaction(1,32'h00400004,0,result);
        transaction(1,32'h0040000c,1,result);
        repeat(3) @(negedge clk);
        if(running || !error) $fatal(1,"Invalid generation configuration not rejected");
        check_read(32'h00400000,6);
        @(negedge clk);host_en=1;host_we=0;host_addr=0;
        repeat(3) @(negedge clk);rst_n=0;
        #1;if(host_ready || host_rdata!==0) $fatal(1,"Host reset cancellation");
        @(negedge clk);host_en=0;rst_n=1;
        repeat(2) @(negedge clk);check_read(0,32'h12345678);
        $display("LLM_PROTOCOL_PASS transactions=%0d cancellations=6 bounds=768KiB",checks);$finish;
    end
    initial begin #1000000;$fatal(1,"LLM_PROTOCOL_TIMEOUT");end
endmodule
