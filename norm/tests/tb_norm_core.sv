`timescale 1ns/1ps
module tb_norm_core;
    parameter USE_TM=0;
    logic clk=0, rst_n=0;
    wire ready, overflow, carry;
    wire [8:0] pc;
    wire [12:0] instr;
    wire [511:0] debug_data;
    logic [511:0] initial_words[0:127], expected[0:79], final_words[0:127], snapshots[0:639];
    logic expected_flags[0:4];
    logic [12:0] instructions[0:511];
    int retired=0, writes=0, tm_starts=0, tm_finishes=0;
    int norm_pcs[0:4]='{0,1,2,4,5};
    always #5 clk=~clk;
    matmulfree #(.NORM_LUT_FILE("normContent.mif")) dut(
        rst_n,clk,ready,overflow,carry,pc,instr,debug_data);
    defparam dut.mem_mapping_inst.MEM_DEPTH=9216;
    defparam dut.mem_mapping_inst.INIT_FILE="";

    task automatic initialize;
        for(int i=0;i<128;i++) dut.register_inst.mem[i]=initial_words[i];
        for(int i=0;i<512;i++) dut.ins_mem.mem[i]=13'h1fff;
        for(int i=0;i<6;i++) dut.ins_mem.mem[i+USE_TM]=instructions[i];
        if(USE_TM) begin
            dut.ins_mem.mem[0]={4'b1000,3'd6,3'd7,3'd0};
            dut.ins_mem.mem[7]={4'b1000,3'd5,3'd6,3'd0};
            for(int i=0;i<9216;i++) dut.mem_mapping_inst.mem[i]='0;
            for(int i=0;i<512;i++) begin
                dut.mem_mapping_inst.mem[7*16+i/32][(i%32)*16+:16]=16'(i*13-1729);
                dut.mem_mapping_inst.mem[1024+(i*512+i)/256][((i*512+i)%256)*2+:2]=2'b01;
            end
        end
    endtask

    initial begin : run_test
        int cycles, beat, dest, source;
        $readmemh("core-initial.hex",initial_words);
        $readmemh("core-expected.hex",expected);
        $readmemh("core-final.hex",final_words);
        $readmemh("core-snapshots.hex",snapshots);
        $readmemh("core-flags.hex",expected_flags);
        $readmemb("instruction.mem",instructions);
        repeat(3) @(negedge clk);
        initialize();
        if(!USE_TM) begin
            // Abort a partially written bank; reset is cancellation, not rollback.
            rst_n=1;
            while(writes<6) begin
                @(posedge clk); if(dut.norm_write) writes++;
                #1;
            end
            @(negedge clk); rst_n=0;
            #1;
            if(dut.norm_write || dut.norm_done || dut.norm_own || ready)
                $fatal(1,"Core reset did not cancel NORM");
            repeat(3) @(negedge clk);
            initialize(); writes=0;
        end
        rst_n=1; cycles=0; beat=0;
        while(!ready) begin
            @(posedge clk);
            if(dut.tmatmul_start) tm_starts++;
            if(dut.tmatmul_done) tm_finishes++;
            if(dut.norm_own) begin
                if(dut.register_stream_busy || dut.memory_busy || dut.reg_wr_en_wb)
                    $fatal(1,"NORM claimed register before prior work drained");
                if(dut.pc!==9'(norm_pcs[retired]+USE_TM)) $fatal(1,"PC moved during NORM");
            end
            if(dut.instr_de[12:9]==7 || dut.instr_em[12:9]==7 || dut.instr_wb[12:9]==7)
                $fatal(1,"NORM leaked into combinational ALU pipeline");
            if(dut.norm_write) begin
                if(retired>=5 || beat>=16 || dut.norm_write_data!==expected[retired*16+beat])
                    $fatal(1,"Core NORM retire=%0d beat=%0d got=%h expected=%h",retired,beat,dut.norm_write_data,expected[retired*16+beat]);
                dest=int'(instructions[norm_pcs[retired]][8:6])*16;
                source=int'(instructions[norm_pcs[retired]][2:0])*16;
                if(dut.norm_write_address!==10'(dest+beat) || dut.norm_read_address!==10'(source+beat))
                    $fatal(1,"Core NORM word/lane addressing");
                beat++; writes++;
            end
            if(dut.norm_done) begin
                if(retired>=5 || beat!=16 || overflow!==expected_flags[retired] || carry!==0 ||
                   instr!==instructions[norm_pcs[retired]] || pc!==9'(norm_pcs[retired]+USE_TM))
                    $fatal(1,"NORM retire count/flags/debug");
                for(int i=0;i<128;i++)
                    if(dut.register_inst.mem[i]!==snapshots[retired*128+i])
                        $fatal(1,"Core register snapshot retire=%0d address=%0d got=%h expected=%h",retired,i,dut.register_inst.mem[i],snapshots[retired*128+i]);
                retired++; beat=0;
            end
            #1; cycles++;
            if(cycles>35000) $fatal(1,"Core deadlock pc=%0d norm_state=%0d",dut.pc,dut.norm_dispatch_inst.state);
        end
        if(retired!=5 || writes!=80 || tm_starts!=2*USE_TM || tm_finishes!=2*USE_TM)
            $fatal(1,"Early HALT or duplicate execution norm=%0d writes=%0d tm=%0d/%0d",retired,writes,tm_starts,tm_finishes);
        for(int i=0;i<128;i++)
            if(dut.register_inst.mem[i]!==final_words[i]) $fatal(1,"Final register mismatch address=%0d",i);
        if(USE_TM) for(int i=0;i<512;i++)
            if(dut.mem_mapping_inst.mem[5*16+i/32][(i%32)*16+:16]!==16'(i*13-1729))
                $fatal(1,"TMATMUL result corrupted across NORM");
        $display("NORM_CORE_PASS instructions=%0d writes=%0d in_place=1 consecutive=1 add_dependency=1 reset=%0d tm_frames=%0d cycles=%0d",
                 retired,writes,!USE_TM,tm_finishes,cycles);
        $finish;
    end
    initial begin #400000; $fatal(1,"Core global watchdog"); end
endmodule
