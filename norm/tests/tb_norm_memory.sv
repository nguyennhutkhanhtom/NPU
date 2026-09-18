`timescale 1ns/1ps
module tb_norm_memory;
    logic clk=0,rst_n=0;
    wire ready,overflow,carry;
    wire [8:0] pc;
    wire [12:0] instr;
    wire [511:0] debug_data;
    logic [511:0] initial_words[0:127],expected[0:79];
    int writes=0,retired=0;
    always #5 clk=~clk;
    matmulfree #(.NORM_LUT_FILE("normContent.mif")) dut(rst_n,clk,ready,overflow,carry,pc,instr,debug_data);
    defparam dut.mem_mapping_inst.MEM_DEPTH=9216;
    defparam dut.mem_mapping_inst.INIT_FILE="";
    initial begin
        $readmemh("core-initial.hex",initial_words);
        $readmemh("core-expected.hex",expected);
        repeat(3) @(negedge clk);
        for(int i=0;i<128;i++) dut.register_inst.mem[i]='0;
        for(int i=0;i<9216;i++) dut.mem_mapping_inst.mem[i]='0;
        for(int i=0;i<16;i++) dut.mem_mapping_inst.mem[6*16+i]=initial_words[7*16+i];
        for(int i=0;i<512;i++) dut.ins_mem.mem[i]=13'h1fff;
        dut.ins_mem.mem[0]={4'd9,3'd7,3'd0,3'd6};  // LDV R7, V6
        dut.ins_mem.mem[1]={4'd7,3'd7,3'd0,3'd7};  // NORM R7, R7
        dut.ins_mem.mem[2]={4'd10,3'd5,3'd0,3'd7}; // STV V5, R7
        dut.ins_mem.mem[3]={4'd9,3'd6,3'd0,3'd5};  // LDV R6, V5
        dut.ins_mem.mem[4]={4'd7,3'd6,3'd0,3'd6};  // NORM R6, R6
        rst_n=1;
        for(int cycle=0;cycle<2000;cycle++) begin
            @(posedge clk);
            if(dut.norm_write) begin
                if(writes>=32 || dut.norm_write_data!==expected[writes])
                    $fatal(1,"Memory/NORM result word=%0d got=%h expected=%h",writes,dut.norm_write_data,expected[writes]);
                writes++;
            end
            if(dut.norm_done) retired++;
            #1;
            if(ready) begin
                if(retired!=2 || writes!=32) $fatal(1,"Memory/NORM early HALT");
                for(int i=0;i<16;i++) begin
                    if(dut.mem_mapping_inst.mem[5*16+i]!==expected[i]) $fatal(1,"Stored NORM word=%0d",i);
                    if(dut.register_inst.mem[6*16+i]!==expected[16+i]) $fatal(1,"Reloaded NORM word=%0d",i);
                end
                $display("NORM_MEMORY_PASS load_norm_store_reload_norm=1 writes=32 cycles=%0d",cycle);
                $finish;
            end
        end
        $fatal(1,"Memory/NORM watchdog pc=%0d",dut.pc);
    end
endmodule
