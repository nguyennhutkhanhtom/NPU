`timescale 1ns/1ps
module tb_scaled_ddr;
  logic clk=0;always #5 clk=~clk;
  logic rst=1,req=0,rv=0,ardy=1;
  logic [3:0] len=2;logic [13:0] base=0;
  wire [13:0] addr; wire [255:0] rd,wd;wire [2:0] cmd;
  wire valid,wreq,rf,wf,finish,en,wend,wwren;
  mem_burst #(.MEM_DATA_BITS(256),.ADDR_BITS(14),.LEN_BITS(4)) dut(
    .rst(rst),.mem_clk(clk),.rd_burst_req(req),.wr_burst_req(1'b0),.rd_burst_len(len),.wr_burst_len(4'd1),
    .rd_burst_addr(base),.wr_burst_addr(14'b0),.rd_burst_data_valid(valid),.wr_burst_data_req(wreq),
    .rd_burst_data(rd),.wr_burst_data(256'b0),.rd_burst_finish(rf),.wr_burst_finish(wf),.burst_finish(finish),
    .app_addr(addr),.app_cmd(cmd),.app_en(en),.app_wdf_data(wd),.app_wdf_end(wend),.app_wdf_wren(wwren),
    .app_rd_data({256{1'b1}}),.app_rd_data_end(1'b1),.app_rd_data_valid(rv),.app_rdy(ardy),.app_wdf_rdy(1'b1),
    .ui_clk_sync_rst(1'b0),.init_calib_complete(1'b1));
  task automatic tick;@(posedge clk);#1;endtask
  initial begin
    tick();@(negedge clk);rst=0;req=1;
    tick();@(negedge clk);req=0;repeat(2) tick();
    if(en!==0 || addr!==16 || $bits(dut.rd_addr_cnt)!=4) $fatal(1,"Scaled read commands");
    @(negedge clk);rv=1;repeat(2) tick();
    if(rf!==1 || rd!=={256{1'b1}}) $fatal(1,"Scaled read data");
    @(negedge clk);rst=1;rv=0;tick();
    @(negedge clk);rst=0;req=1;base=14'd2048;ardy=0;tick();
    if(addr!==0) $fatal(1,"Original address truncation unexpectedly fixed");
    @(negedge clk);rst=1;req=0;tick();
    @(negedge clk);rst=0;req=1;len=0;base=0;ardy=1;tick();
    @(negedge clk);req=0;repeat(40) tick();
    if(dut.state!=1 || rf!==0 || en!==1) $fatal(1,"Original zero-length bug unexpectedly fixed");
    $display("SCALED_DDR_PASS data=256 address=14 length=4 legacy_boundary_bugs_retained");$finish;
  end
endmodule
