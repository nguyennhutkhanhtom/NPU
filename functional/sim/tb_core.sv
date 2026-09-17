`timescale 1ns/1ps
module tb_core;
    parameter W=8;
    localparam WW=W*32,MW=(512*512*2)/WW,DEPTH=(W==8 ? 32768 : 524288);
    logic clk=0,rst_n=0,ready,ov,carry;
    wire [(W==8 ? 6 : 9)-1:0] pc;
    wire [12:0] instr;
    wire [WW-1:0] debug_mem;
    always #5 clk=~clk;
    matmulfree #(.DATA_WIDTH(W),.FRAC_WIDTH(W-4),.REG_DEPTH(W==8 ? 128 : 1024),
        .MEM_DEPTH(DEPTH),.INSTR_DEPTH(W==8 ? 64 : 512),
        .MEM_INIT_FILE(W==8 ? "functional/assets/memory_8.hex" : "functional/assets/memory_16.hex"),
        .INSTR_INIT_FILE(W==8 ? "functional/assets/program_8.bin" : "functional/assets/program_16.bin"),
        .SIG_INIT_FILE(W==8 ? "functional/assets/sig_8.bin" : "functional/assets/sig_16.bin"),
        .EXP_INIT_FILE(W==8 ? "functional/assets/exp_8.hex" : "functional/assets/exp_16.hex")
    ) dut(.clk(clk),.rst_n(rst_n),.ready(ready),.overflow_out(ov),.carry_out(carry),
        .pc_debug(pc),.instr_debug(instr),.mem_out_1_debug(debug_mem));
    logic [WW-1:0] golden_reg[0:127],golden_mem[0:1024+8*MW-1],golden_trace[0:23*16-1];
    integer retired=0,cycles=0;
    always @(negedge clk) if(rst_n) begin
        cycles++;
        if(cycles>30000) $fatal(1,"CORE timeout W=%0d phase=%0d pc=%0d",W,dut.phase,dut.pc);
        if(dut.complete) begin : commit_check
            integer base;
            base=int'(dut.instr_de[8:6])*16;
            if(dut.opcode==10) base=base+int'(dut.instr_de[5:3])*128;
            for(int j=0;j<16;j++) begin
                if(dut.opcode==8 || dut.opcode==10) begin
                    if(dut.mem_mapping_inst.mem[base+j]!==golden_trace[retired*16+j])
                        $fatal(1,"CORE memory commit W=%0d pc=%0d word=%0d got=%h expected=%h",
                            W,dut.pc,base+j,dut.mem_mapping_inst.mem[base+j],golden_trace[retired*16+j]);
                end else if(dut.register_inst.mem[base+j]!==golden_trace[retired*16+j])
                    $fatal(1,"CORE register commit W=%0d pc=%0d word=%0d got=%h expected=%h",
                        W,dut.pc,base+j,dut.register_inst.mem[base+j],golden_trace[retired*16+j]);
            end
            retired++;
        end
    end
    initial begin
        $readmemh(W==8 ? "functional/assets/golden_reg_8.hex" : "functional/assets/golden_reg_16.hex",golden_reg);
        $readmemh(W==8 ? "functional/assets/golden_mem_8.hex" : "functional/assets/golden_mem_16.hex",golden_mem);
        $readmemh(W==8 ? "functional/assets/golden_trace_8.hex" : "functional/assets/golden_trace_16.hex",golden_trace);
        repeat(3) @(negedge clk);
        rst_n=1;
        wait(ready);
        @(negedge clk);
        if(retired!=23 || instr[12:9]!=15 || instr[8:0]==9'h1ff) $fatal(1,"CORE HALT/retirement");
        for(int i=0;i<128;i++) if(dut.register_inst.mem[i]!==golden_reg[i]) $fatal(1,"CORE final register %0d",i);
        for(int i=0;i<1024+8*MW;i++) if(dut.mem_mapping_inst.mem[i]!==golden_mem[i])
            $fatal(1,"CORE final memory %0d",i);
        repeat(8) @(negedge clk);
        if(!ready || retired!=23) $fatal(1,"HALT not sticky");
        $display("CORE_PASS W=%0d retired=%0d cycles=%0d",W,retired,cycles);
        $finish;
    end
endmodule
