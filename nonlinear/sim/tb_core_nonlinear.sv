`timescale 1ns/1ps
module tb_core_nonlinear;
    parameter MIXED=0;
    logic clk=0,rst_n=0;
    wire ready,overflow,carry;
    wire [8:0] pc;
    wire [12:0] instr;
    wire [511:0] debug_data;
    logic [511:0] initial_words[0:15],expected[0:95];
    logic expected_flags[0:5];
    logic [12:0] program_words[0:63];
    int retired=0,writes=0;
    always #5 clk=~clk;
    matmulfree dut(rst_n,clk,ready,overflow,carry,pc,instr,debug_data);
    initial begin : test
        int cycles,beat,dest;
        $readmemh("../../assets/dispatch_initial_16.hex",initial_words);
        $readmemh(MIXED?"../../assets/mixed_expected_16.hex":"../../assets/dispatch_expected_16.hex",expected);
        $readmemh(MIXED?"../../assets/mixed_flags_16.hex":"../../assets/dispatch_flags_16.hex",expected_flags);
        $readmemb(MIXED?"../../assets/mixed_program_16.mem":"../../assets/dispatch_program_16.mem",program_words);
        repeat(3) @(negedge clk);
        for(int i=0;i<512;i++) dut.ins_mem.mem[i]=13'h1fff;
        for(int i=0;i<64;i++) dut.ins_mem.mem[i]=program_words[i];
        for(int i=0;i<128;i++) dut.register_inst.mem[i]='0;
        for(int i=0;i<16;i++) dut.register_inst.mem[i]=initial_words[i];
        rst_n=1;cycles=0;beat=0;
        while(!ready) begin
            @(posedge clk);
            if(dut.nl_write) begin
                if(retired>=6 || beat>=16 || dut.nl_data!==expected[retired*16+beat])
                    $fatal(1,"CORE nonlinear write retire=%0d beat=%0d got=%h exp=%h",retired,beat,dut.nl_data,expected[retired*16+beat]);
                beat++;writes++;
            end
            if(dut.nl_done) begin
                if(retired>=6 || beat!=16 || instr!==program_words[retired+MIXED] || pc!==9'(retired+MIXED) ||
                   overflow!==expected_flags[retired] || carry!==0)
                    $fatal(1,"CORE nonlinear commit mismatch");
                dest=int'(program_words[retired+MIXED][8:6])*16;
                for(int i=0;i<16;i++) if(dut.register_inst.mem[dest+i]!==expected[retired*16+i]) $fatal(1,"CORE RAM mismatch");
                retired++;beat=0;
            end
            #1;cycles++;
            if(cycles>150000) $fatal(1,"CORE nonlinear deadlock PC=%0d state=%0d",dut.pc,dut.nonlinear_inst.state);
        end
        if(retired!=6 || writes!=96) $fatal(1,"Missing nonlinear instructions");
        $display("CORE_NONLINEAR_PASS mixed=%0d instructions=%0d writes=%0d cycles=%0d TMATMUL=inactive_stub",MIXED,retired,writes,cycles);$finish;
    end
endmodule
