`timescale 1ns/1ps
module tb_control;
    parameter W=8;
    localparam WW=W*32,MW=(512*512*2)/WW;
    logic clk=0,rst_n=0;
    always #5 clk=~clk;
    wire ready,overflow,carry;
    wire [1:0] pc;
    wire [12:0] committed;
    wire [WW-1:0] debug_mem;
    logic [12:0] decode_instr;
    wire rw,rr,mw,mr0,mr1,wb;
    wire [2:0] alu;
    ctrl_unit decoder(.instr(decode_instr),.reg_wr_en(rw),.reg_rd_en(rr),.mem_wren(mw),
        .mem_rden_0(mr0),.mem_rden_1(mr1),.wb_sel(wb),.alu_op(alu));
    matmulfree #(.DATA_WIDTH(W),.REG_DEPTH(128),.MEM_DEPTH(1024+8*MW),.INSTR_DEPTH(3),
        .MEM_INIT_FILE(""),.INSTR_INIT_FILE(""),
        .SIG_INIT_FILE(W==8 ? "functional/assets/sig_8.bin" : "functional/assets/sig_16.bin"),
        .EXP_INIT_FILE(W==8 ? "functional/assets/exp_8.hex" : "functional/assets/exp_16.hex")
    ) dut(.clk(clk),.rst_n(rst_n),.ready(ready),.overflow_out(overflow),.carry_out(carry),
        .pc_debug(pc),.instr_debug(committed),.mem_out_1_debug(debug_mem));
    task automatic reset_core;
        @(negedge clk);rst_n=0;
        repeat(2) @(negedge clk);
    endtask
    task automatic halt_check(input int operand);
        reset_core();
        dut.ins_mem.mem[0]=13'h1e00|13'(operand);
        rst_n=1;
        wait(ready);@(negedge clk);
        if(committed!==(13'h1e00|13'(operand)) || pc!==0) $fatal(1,"HALT operand decode");
    endtask
    initial begin : run_tests
        int op;
        for(int instruction=0;instruction<8192;instruction++) begin
            decode_instr=13'(instruction);op=instruction>>9;#1;
            if(rw!==(op>=1 && op<=7 || op==9) || rr!==(op>=1 && op<=7 || op==10) ||
               mw!==(op==8 || op==10) || mr0!==(op==8 || op==9) || mr1!==(op==8))
                $fatal(1,"Decoder flags op=%0d",op);
        end
        decode_instr='x;#1;
        if({rw,rr,mw,mr0,mr1,wb,alu}!==0) $fatal(1,"Unknown opcode caused side effect");
        for(int i=0;i<512;i++) halt_check(i);
        reset_core();
        for(int i=0;i<3;i++) dut.ins_mem.mem[i]=0;
        rst_n=1;wait(ready);@(negedge clk);
        if(pc!==2 || !dut.pc_exhausted) $fatal(1,"Non-power-of-two ROM bound");
        // Abort load/store/RMS/TMATMUL after start and restart at a fresh HALT.
        for(int test=0;test<4;test++) begin
            reset_core();
            for(int i=0;i<128;i++) dut.register_inst.mem[i]='0;
            for(int i=0;i<1024+MW;i++) dut.mem_mapping_inst.mem[i]='0;
            case(test)
                0: dut.ins_mem.mem[0]=13'(9<<9);
                1: dut.ins_mem.mem[0]=13'(10<<9);
                2: dut.ins_mem.mem[0]=13'(7<<9);
                3: dut.ins_mem.mem[0]=13'(8<<9);
            endcase
            rst_n=1;wait(dut.phase==dut.RUN);repeat(4) @(negedge clk);
            reset_core();
            if(dut.v_em || dut.v_mw || dut.v_wb || dut.mem_valid_0 || dut.rf_valid || dut.tm_valid)
                $fatal(1,"Pipeline reset retained valid");
            dut.ins_mem.mem[0]=13'h1e00;rst_n=1;wait(ready);@(negedge clk);
            if(committed!==13'h1e00) $fatal(1,"Pipeline reset restart");
        end
        $display("CONTROL_PASS W=%0d decodes=8192 halts=512 busy_resets=4 pc_depth=3",W);$finish;
    end
    initial begin #100000;$fatal(1,"CONTROL watchdog");end
endmodule
