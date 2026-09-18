`timescale 1ns/1ps
module tb_core;
    logic clk=0,rst_n=0;
    wire ready,overflow,carry;
    wire [8:0] pc;
    wire [12:0] instr;
    wire [511:0] debug_data;
    int starts=0,finishes=0,writes=0;
    always #5 clk=~clk;
    matmulfree dut(rst_n,clk,ready,overflow,carry,pc,instr,debug_data);
    // Keep the actual processor, arithmetic, memory and ternary engine.
    // Only memory capacity is reduced for simulation; all TM selectors fit.
    defparam dut.mem_mapping_inst.MEM_DEPTH=9216;
    defparam dut.mem_mapping_inst.INIT_FILE="";
    initial begin
        repeat(3) @(negedge clk);
        for(int i=0;i<512;i++) dut.ins_mem.mem[i]=13'h1fff;
        dut.ins_mem.mem[0]={4'b1000,3'd6,3'd7,3'd7};
        dut.ins_mem.mem[1]={4'b1000,3'd5,3'd6,3'd0};
        dut.ins_mem.mem[2]={4'b1000,3'd5,3'd5,3'd7};
        for(int i=0;i<9216;i++) dut.mem_mapping_inst.mem[i]='0;
        for(int i=0;i<512;i++) begin
            dut.mem_mapping_inst.mem[7*16+i/32][(i%32)*16+:16]=16'(i*13-1729);
            dut.mem_mapping_inst.mem[1024+(i*512+i)/256][((i*512+i)%256)*2+:2]=2'b01;
            dut.mem_mapping_inst.mem[8192+(i*512+i)/256][((i*512+i)%256)*2+:2]=2'b01;
        end
        rst_n=1;
        for(int cycles=0;cycles<50000;cycles++) begin
            @(posedge clk);
            if(dut.tmatmul_start) starts++;
            if(dut.tmatmul_done) finishes++;
            if(dut.tmatmul_write && dut.tmatmul_ready) begin
                for(int lane=0;lane<32;lane++)
                    if(dut.result[lane*16+:16]!==16'(((writes%16)*32+lane)*13-1729))
                        $fatal(1,"Core TM result frame=%0d beat=%0d",finishes,writes%16);
                writes++;
            end
            #1;
            if(ready) begin
                if(starts!=3 || finishes!=3 || writes!=48) $fatal(1,"Core early halt/duplicate TM starts=%0d finishes=%0d writes=%0d",starts,finishes,writes);
                for(int i=0;i<512;i++)
                    if(dut.mem_mapping_inst.mem[5*16+i/32][(i%32)*16+:16]!==16'(i*13-1729)) $fatal(1,"Core destination mismatch");
                $display("CORE_PASS frames=3 writes=48 back_to_back=1 in_place=1 halt_drained=1 cycles=%0d",cycles);$finish;
            end
        end
        $fatal(1,"Core watchdog starts=%0d finishes=%0d writes=%0d pc=%0d instr=%h",starts,finishes,writes,pc,instr);
    end
endmodule
