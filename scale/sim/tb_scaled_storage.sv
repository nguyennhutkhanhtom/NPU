`timescale 1ns/1ps
module tb_scaled_storage;
    logic clk=0; always #5 clk=~clk;
    logic rst_n=0;
    logic [255:0] data='1,r0,r1,m0,m1;
    logic [2:0] ra0=7,ra1=3,wa=7;
    logic rwe=0,mwe=0,mre=0,mode=0;
    wire full,empty,af,ae,rf,wf,fe,maf,mae;
    register #(.DATA_WIDTH(8),.MEM_DEPTH(128)) regs(.clk(clk),.rst_n(rst_n),.data_in(data),.r_addr_0(ra0),.r_addr_1(ra1),.w_addr(wa),
      .w_en(rwe),.rd_en(1'b0),.full(full),.empty(empty),.almost_full(af),.almost_empty(ae),.data_out_0(r0),.data_out_1(r1));
    mem_mapping #(.DATA_WIDTH(8),.MEM_DEPTH(16384),.INIT_FILE("mem_init_8.mem")) ram(.clk(clk),.rst_n(rst_n),.data_in(data),
      .r_addr_0(ra0),.r_addr_1(ra1),.w_addr(wa),.w_en(mwe),.rd_en_0(mre),.rd_en_1(1'b0),.rd_type(mode),.tmatmul_write(1'b0),
      .read_finish(rf),.write_finish(wf),.fifo_1_empty(fe),.almost_full(maf),.almost_empty(mae),.data_out_0(m0),.data_out_1(m1));
    logic [7:0] terms[511:0]; wire [7:0] acc;
    acc_mul #(.DATA_WIDTH(8)) sum(terms,acc);
    logic [7:0] expected;
    task automatic tick; @(posedge clk); #1; endtask
    initial begin
      for(int i=0;i<512;i++) terms[i]=0;
      // Impulse each of the 512 leaves: catches accidental scaling of tree dimensions.
      for(int i=0;i<512;i++) begin
        terms[i]=8'h07;#1;
        if(acc!==7) $fatal(1,"Missing accumulator leaf %0d",i);
        terms[i]=0;
      end
      expected=0;
      for(int i=0;i<512;i++) begin terms[i]=i;expected=expected+terms[i];end
      #1;if(acc!==expected) $fatal(1,"Modulo accumulator changed");
      tick();@(negedge clk);rst_n=1;
      if($bits(regs.w_ptr)!=7 || $bits(ram.r_ptr_0)!=14) $fatal(1,"Physical pointer widths not scaled");
      #1;if(ram.v_index!==0) $fatal(1,"F07 unexpectedly fixed");
      @(negedge clk);rwe=1;mwe=1;repeat(2) tick();repeat(16) tick();
      if(regs.mem[127]!=='1) $fatal(1,"Last register word missing");
      if(ram.mem[126]!=='1 || ram.mem[127]==='1) $fatal(1,"Original memory last-word behavior changed");
      @(negedge clk);rwe=0;mwe=0;mode=1;mre=1;
      repeat(2) tick();
      if(ram.r_ptr_0!=14336 || ram.r_ptr_0_end!=16383 || ram.r_addr_1_decode!=2096) $fatal(1,"Scaled matrix map");
      @(negedge clk);mre=0;repeat(2047) tick();
      if(ram.r_ptr_0!=16383 || rf!==1) $fatal(1,"Scaled frame length");
      $display("SCALED_STORAGE_PASS data=8 reg_ptr=7 mem_ptr=14 matrix_words=2048 accumulator_leaves=512");$finish;
    end
endmodule
