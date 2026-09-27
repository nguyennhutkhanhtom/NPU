`timescale 1ns/1ps
module tb_parallel;
    parameter CASE = 0;
    logic clk=0, rst_n=0, allow_output=1;
    wire ready, overflow, carry;
    wire [8:0] pc;
    wire [12:0] instr;
    wire [511:0] debug_data;
    logic [15:0] sig_table [0:1023];
    logic [15:0] expected [0:7][0:511];
    int reg_writes [0:7];
    int starts=0, finishes=0, tm_writes=0, overlap_words=0, tail_wait=0;
    int cycles=0, expected_frames, expected_alu_words;
    int first_overlap_cycle=-1, last_overlap_cycle=-1, first_tm_done_cycle=-1;
    bit monitor=0;
    always #5 clk=~clk;
    matmulfree #(.NORM_LUT_FILE("normContent.mif")) dut(
        rst_n,clk,ready,overflow,carry,pc,instr,debug_data);
    defparam dut.mem_mapping_inst.MEM_DEPTH=9216;
    defparam dut.mem_mapping_inst.INIT_FILE="";

    function automatic [12:0] ins(input int op,dst,b,a);
        return {4'(op),3'(dst),3'(b),3'(a)};
    endfunction

    task automatic initialize;
        int p, index;
        starts=0; finishes=0; tm_writes=0; overlap_words=0;
        tail_wait=0; cycles=0;
        first_overlap_cycle=-1; last_overlap_cycle=-1; first_tm_done_cycle=-1;
        expected_frames=(CASE==3)?2:1;
        expected_alu_words=(CASE==4 || CASE==9 || CASE==10)?0:
            ((CASE==3 || CASE==5 || CASE==6 || CASE==8)?16:48);
        for(int b=0;b<8;b++) reg_writes[b]=0;
        for(int i=0;i<9216;i++) dut.mem_mapping_inst.mem[i]='0;
        for(int i=0;i<1024;i++) dut.register_inst.mem[i]='0;
        for(int i=0;i<512;i++) begin
            expected[0][i]=16'(i*3-500);
            expected[1][i]=16'(i*2+64);
            expected[2][i]=16'(i*5-436);
            expected[3][i]=expected[0][i];
            index=(int'(expected[3][i])>>6)^512;
            expected[4][i]=sig_table[index];
            expected[5][i]=(CASE==5)?expected[0][i]:16'(i*7-1000);
            if(CASE==8) expected[5][i]=expected[1][i];
            if(CASE==6) expected[3][i]=expected[5][i]-expected[1][i];
            dut.register_inst.mem[i/32][(i%32)*16+:16]=expected[0][i];
            dut.register_inst.mem[16+i/32][(i%32)*16+:16]=expected[1][i];
            // Case 5 must actually overwrite different memory before TM reads it.
            dut.mem_mapping_inst.mem[7*16+i/32][(i%32)*16+:16]=
                (CASE==8)?expected[1][i]:16'(i*7-1000);
            dut.mem_mapping_inst.mem[1024+(i*512+i)/256][((i*512+i)%256)*2+:2]=2'b01;
            dut.ins_mem.mem[i]=13'h1fff;
        end
        p=0;
        if(CASE==5) dut.ins_mem.mem[p++]=ins(10,7,0,0); // STV before TM
        if(CASE==8) dut.ins_mem.mem[p++]=ins(9,1,0,7);  // LDV before TM
        dut.ins_mem.mem[p++]=ins(8,6,7,0);
        if(CASE==3) dut.ins_mem.mem[p++]=ins(8,5,6,0); // back-to-back, dependent TM
        if(CASE!=4 && CASE!=9 && CASE!=10) dut.ins_mem.mem[p++]=ins(1,2,1,0);
        if(CASE==0 || CASE==1 || CASE==2 || CASE==7 || CASE==11) begin
            dut.ins_mem.mem[p++]=ins(2,3,1,2); // dependent SUB
            dut.ins_mem.mem[p++]=ins(6,4,0,3); // dependent SIG, real LUT
        end
        if(CASE==1 || CASE==5 || CASE==6 || CASE==10 || CASE==11) dut.ins_mem.mem[p++]=ins(9,5,0,6);
        if(CASE==6) dut.ins_mem.mem[p++]=ins(2,3,1,5);
        if(CASE==2 || CASE==6) dut.ins_mem.mem[p++]=ins(10,5,0,(CASE==2)?4:3);
        if(CASE==9) dut.ins_mem.mem[p++]=ins(10,5,0,0);
    endtask

    always @(posedge clk) begin : observe
        int bank, word_index, i;
        if(rst_n && monitor) begin
            cycles++;
            if(dut.tmatmul_start) begin
                if(starts!=finishes) $fatal(1,"Overlapping TM starts");
                if(dut.memory_busy) $fatal(1,"TM stole an older memory transaction");
                starts++;
            end
            if(dut.tmatmul_done) begin
                if(first_tm_done_cycle<0) first_tm_done_cycle=cycles;
                finishes++;
            end
            if(dut.tmatmul_write && dut.tmatmul_ready) begin
                for(int lane=0;lane<32;lane++) begin
                    i=(tm_writes%16)*32+lane;
                    if(dut.result[lane*16+:16]!==expected[5][i])
                        $fatal(1,"TM data frame=%0d element=%0d",finishes,i);
                end
                tm_writes++;
            end
            // Every committed register word is checked, not only final contents.
            if(dut.register_inst.state_write==2) begin
                bank=int'(dut.register_inst.w_ptr)/16;
                word_index=int'(dut.register_inst.w_ptr)%16;
                if((bank<2 && !(CASE==8 && bank==1)) || bank>5)
                    $fatal(1,"Unexpected register write bank=%0d",bank);
                if(word_index!=reg_writes[bank])
                    $fatal(1,"Duplicate/missing register word bank=%0d got=%0d expected=%0d",bank,word_index,reg_writes[bank]);
                for(int lane=0;lane<32;lane++)
                    if(dut.wb_data[lane*16+:16]!==expected[bank][word_index*32+lane])
                        $fatal(1,"Register data case=%0d bank=%0d word=%0d lane=%0d got=%h expected=%h pc=%0d",CASE,bank,word_index,lane,dut.wb_data[lane*16+:16],expected[bank][word_index*32+lane],dut.pc);
                reg_writes[bank]++;
                if(dut.tmatmul_assert) begin
                    if(dut.wb_sel_wb) $fatal(1,"LDV wrote register while TM owns memory");
                    if(first_overlap_cycle<0) first_overlap_cycle=cycles;
                    last_overlap_cycle=cycles;
                    overlap_words++;
                end
            end
            if(dut.decode_bubble && dut.tmatmul_assert && dut.read_finish) tail_wait++;
            if(dut.tmatmul_assert) begin
                if(dut.instr_em[12:9]==9 || dut.instr_em[12:9]==10 || dut.instr_em[12:9]==15 ||
                   dut.instr_mw[12:9]==9 || dut.instr_mw[12:9]==10)
                    $fatal(1,"Conflicting instruction escaped decode while TM busy");
                if(dut.mem_mapping_inst.state_read!=0 || dut.mem_mapping_inst.state_write!=0)
                    $fatal(1,"Normal memory FSM active during TM");
            end
            if(cycles>60000) $fatal(1,"Watchdog case=%0d pc=%0d de=%h em=%h tm=%0d regbusy=%b",CASE,dut.pc,dut.instr_de,dut.instr_em,dut.tmatmul_assert,dut.register_stream_busy);
        end
    end

    initial begin
        $readmemb("sigContent.mif",sig_table);
        repeat(3) @(negedge clk);
        initialize(); monitor=1; rst_n=1;
        if(CASE==7) begin
            wait(overlap_words>=8);
            @(negedge clk); monitor=0; rst_n=0;
            repeat(3) @(negedge clk);
            initialize(); monitor=1; rst_n=1;
        end
        wait(ready);
        @(negedge clk);
        if(starts!=expected_frames || finishes!=expected_frames || tm_writes!=16*expected_frames)
            $fatal(1,"Early HALT or lost TM starts=%0d finishes=%0d writes=%0d",starts,finishes,tm_writes);
        if(overlap_words!=expected_alu_words)
            $fatal(1,"ALU did not overlap TM case=%0d words=%0d expected=%0d",CASE,overlap_words,expected_alu_words);
        if(tail_wait==0) $fatal(1,"Did not exercise wait beyond read_finish");
        if(CASE!=4 && CASE!=9 && CASE!=10 && reg_writes[2]!=16) $fatal(1,"Missing ADD output");
        if((CASE==0 || CASE==1 || CASE==2 || CASE==7 || CASE==11) && (reg_writes[3]!=16 || reg_writes[4]!=16))
            $fatal(1,"Missing SUB/SIG output");
        if((CASE==1 || CASE==5 || CASE==6 || CASE==10 || CASE==11) && reg_writes[5]!=16) $fatal(1,"Missing LDV output");
        if(CASE==8 && reg_writes[1]!=16) $fatal(1,"Missing initial LDV output");
        for(int i=0;i<512;i++) begin
            if(dut.mem_mapping_inst.mem[6*16+i/32][(i%32)*16+:16]!==expected[5][i])
                $fatal(1,"TM destination element=%0d",i);
            if(CASE==2 || CASE==6)
                if(dut.mem_mapping_inst.mem[5*16+i/32][(i%32)*16+:16]!==expected[(CASE==2)?4:3][i])
                    $fatal(1,"STV destination case=%0d element=%0d got=%h expected=%h",CASE,i,dut.mem_mapping_inst.mem[5*16+i/32][(i%32)*16+:16],expected[(CASE==2)?4:3][i]);
            if(CASE==9 && dut.mem_mapping_inst.mem[5*16+i/32][(i%32)*16+:16]!==expected[0][i])
                $fatal(1,"Immediate STV destination element=%0d",i);
            if(CASE==3 && dut.mem_mapping_inst.mem[5*16+i/32][(i%32)*16+:16]!==expected[5][i])
                $fatal(1,"Second TM destination element=%0d",i);
        end
        $display("PARALLEL_PASS case=%0d tm_frames=%0d tm_writes=%0d overlap_words=%0d first_overlap=%0d last_overlap=%0d first_tm_done=%0d tail_wait=%0d cycles=%0d",CASE,finishes,tm_writes,overlap_words,first_overlap_cycle,last_overlap_cycle,first_tm_done_cycle,tail_wait,cycles);
        $finish;
    end
    // Stretch the gap between input-read completion and the final output
    // acceptance. Force the shared handshake so engine and memory both stall.
    initial if(CASE==11) begin
        force dut.mem_mapping_inst.tmatmul_ready = allow_output &&
            dut.mem_mapping_inst.tm_active && dut.mem_mapping_inst.tm_write_count < 16;
        wait(rst_n && dut.tmatmul_assert && dut.read_finish);
        @(negedge clk); allow_output=0;
        repeat(40) @(negedge clk);
        if(!dut.decode_bubble || !dut.tmatmul_assert || ready)
            $fatal(1,"Memory instruction released before stalled output accepted");
        allow_output=1;
    end
    initial begin #650000; $fatal(1,"Global watchdog"); end
endmodule
