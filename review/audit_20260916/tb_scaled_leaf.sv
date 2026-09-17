`timescale 1ns/1ps
module tb_scaled_leaf;
  import scaled_leaf_profile::*;
  logic clk=0; always #5 clk=~clk;
  logic rst_n=0;
  logic [WORD_W-1:0] data='1,r0,r1,m0,m1;
  logic [REG_ADDR_W-1:0] rr0=0,rr1=0,rw=3;
  logic we=0,re=0,full,empty,af,ae;
  register #(.DATA_WIDTH(DATA_W),.ADDR_WIDTH(REG_ADDR_W),.MEM_DEPTH(REG_DEPTH)) rf(
    .clk(clk),.rst_n(rst_n),.data_in(data),.r_addr_0(rr0),.r_addr_1(rr1),.w_addr(rw),.w_en(we),.rd_en(re),
    .full(full),.empty(empty),.almost_full(af),.almost_empty(ae),.data_out_0(r0),.data_out_1(r1));
  logic mread=0,mdone,mwdone,mempty,maf,mae;
  mem_mapping #(.DATA_WIDTH(DATA_W),.MEM_DEPTH(MEM_DEPTH)) ram(
    .clk(clk),.rst_n(rst_n),.data_in(data),.r_addr_0(3'd7),.r_addr_1(3'd0),.w_addr(3'd0),
    .w_en(1'b0),.rd_en_0(mread),.rd_en_1(1'b0),.rd_type(1'b1),.tmatmul_write(1'b0),
    .read_finish(mdone),.write_finish(mwdone),.fifo_1_empty(mempty),.data_out_0(m0),.data_out_1(m1),
    .almost_full(maf),.almost_empty(mae));
  logic brst=1,breq=0,bvalid=0;
  wire [BURST_ADDR_W-1:0] addr;
  wire [BURST_DATA_W-1:0] dout,wout;
  wire [2:0] cmd; wire en,wdfend,wdfwen,wreq,rdone,wdone,done,rdvalid;
  mem_burst #(.MEM_DATA_BITS(BURST_DATA_W),.ADDR_BITS(BURST_ADDR_W)) ddr_model(
    .rst(brst),.mem_clk(clk),.rd_burst_req(breq),.wr_burst_req(1'b0),.rd_burst_len(10'd2),.wr_burst_len(10'd1),
    .rd_burst_addr({BURST_ADDR_W{1'b0}}),.wr_burst_addr({BURST_ADDR_W{1'b0}}),
    .rd_burst_data_valid(rdvalid),.wr_burst_data_req(wreq),.rd_burst_data(dout),.wr_burst_data({BURST_DATA_W{1'b0}}),
    .rd_burst_finish(rdone),.wr_burst_finish(wdone),.burst_finish(done),.app_addr(addr),.app_cmd(cmd),.app_en(en),
    .app_wdf_data(wout),.app_wdf_end(wdfend),.app_wdf_wren(wdfwen),.app_rd_data({BURST_DATA_W{1'b1}}),
    .app_rd_data_end(1'b1),.app_rd_data_valid(bvalid),.app_rdy(1'b1),.app_wdf_rdy(1'b1),
    .ui_clk_sync_rst(1'b0),.init_calib_complete(1'b1));
  task automatic tick; @(posedge clk); #1; endtask
  initial begin
    tick(); @(negedge clk);rst_n=1;brst=0;we=1;mread=1;
    repeat(2) tick();
    assert(ram.r_ptr_0==7168 && ram.r_ptr_0_end==8191) else $fatal(1,"memory mapping boundary");
    @(negedge clk);we=0;mread=0;
    repeat(16) tick();
    assert(rf.mem[48]==='1 && rf.mem[63]==='1) else $fatal(1,"scaled register transport");
    @(negedge clk);breq=1;tick(); @(negedge clk);breq=0;
    repeat(2) tick();
    assert(en===0) else $fatal(1,"read command count");
    @(negedge clk);bvalid=1;repeat(2) tick();
    assert(rdone===1 && dout==={BURST_DATA_W{1'b1}}) else $fatal(1,"read response");
    $display("SCALED_LEAF_PASS data=%0d word=%0d reg_addr=%0d reg_depth=%0d mem_depth=%0d burst_addr=%0d",DATA_W,WORD_W,REG_ADDR_W,REG_DEPTH,MEM_DEPTH,BURST_ADDR_W);
    $finish;
  end
  initial begin #2000;$fatal(1,"watchdog");end
endmodule
