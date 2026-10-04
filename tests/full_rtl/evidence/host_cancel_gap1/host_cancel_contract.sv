`timescale 1ns/1ps
// Additional host-only synthetic contract probe; no application/checkpoint.
// Expected values and SRAM write observation never drive internal DUT state.
module tb_host_cancel_contract;
    logic clk=0,rst_n=0,host_en=0,host_we=0;
    logic [31:0] host_addr=0,host_wdata=0,host_rdata;
    logic host_ready,running,ready,error,overflow_out;
    logic [8:0] pc_debug;
    logic [12:0] instr_debug;
    llm_soc dut(.*);
    always #5 clk=~clk;
    integer phase,checks=0,commits=0,second_commits=0;
    logic [31:0] canceled_value,new_value,response;
    // The replaceable leaf contract commits on the edge with wr_en asserted.
    // Observe the real IP boundary, including its captured address/data.
    always @(posedge clk) begin
        if(dut.u_parameters.g_ram_lane[0].u_storage.g_ip.u_storage.wr_en) begin
            if(dut.u_parameters.g_ram_lane[0].u_storage.g_ip.u_storage.wr_addr==0 &&
               dut.u_parameters.g_ram_lane[0].u_storage.g_ip.u_storage.wr_data===canceled_value)
                commits++;
            if(dut.u_parameters.g_ram_lane[0].u_storage.g_ip.u_storage.wr_addr==1 &&
               dut.u_parameters.g_ram_lane[0].u_storage.g_ip.u_storage.wr_data===new_value)
                second_commits++;
        end
    end
    task automatic transaction(input bit write,input logic [31:0] address,data,
                               output logic [31:0] result,input bit start_now=0);
        integer waits;
        if(!start_now) @(negedge clk);
        host_en=1;host_we=write;host_addr=address;host_wdata=data;waits=0;
        while(!host_ready && waits<16) begin @(negedge clk);waits++;end
        if(!host_ready) $fatal(1,"Probe host timeout address=%h",address);
        if(write && address==32 && data===new_value && second_commits!=1)
            $fatal(1,"New write ACK before its own leaf commit phase=%0d commits=%0d",phase,second_commits);
        result=host_rdata;
        @(negedge clk);host_en=0;host_we=0;
        @(negedge clk);if(host_ready) $fatal(1,"Canceled/retired response escaped");
    endtask
    initial begin
        repeat(3) @(negedge clk);rst_n=1;
        repeat(2) @(negedge clk);
        for(phase=1;phase<=7;phase++) begin
            transaction(1,0,32'h12345678,response);
            canceled_value=32'hab000000+phase;new_value=32'hcd000000+phase;
            commits=0;second_commits=0;
            @(negedge clk);host_en=1;host_we=1;host_addr=0;host_wdata=canceled_value;
            repeat(phase) @(negedge clk);
            host_en=0;host_we=0;
            @(negedge clk);if(host_ready) $fatal(1,"Canceled write response escaped phase=%0d",phase);
            // Immediate next transaction after the required idle edge.
            transaction(1,32,new_value,response,1);
            transaction(0,0,0,response);
            if(response!==(phase==1 ? 32'h12345678 : canceled_value))
                $fatal(1,"Write acceptance contract phase=%0d actual=%h",phase,response);
            if(commits!=(phase==1 ? 0 : 1)) $fatal(1,"Canceled write committed wrong count phase=%0d count=%0d",phase,commits);
            checks++;
            transaction(0,32,0,response);
            if(response!==new_value || second_commits!=1)
                $fatal(1,"New request payload/commit mismatch phase=%0d actual=%h",phase,response);
            checks++;
        end
        if(running || error) $fatal(1,"Host-only probe unexpectedly launched graph");
        $display("HOST_CANCEL_CONTRACT_PASS phases=7 checks=%0d pre_execute_cancel=1 accepted_write_commits=6 own_commit_before_ack=7 idle_edges=1",checks);
        $finish;
    end
    initial begin #1000000;$fatal(1,"HOST_CANCEL_CONTRACT_TIMEOUT");end
endmodule
