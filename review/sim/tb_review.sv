`timescale 1ns/1ps
`include "scaled_config.svh"
module tb_review;
  logic clk=0;
  always #5 clk=~clk;
  logic rst_n=0;
  int checks=0, reproduced=0;
  task automatic evidence(input string id, input bit bug_present);
    checks++;
    if (bug_present) begin reproduced++; $display("REPRODUCED %s",id); end
    else $display("NOT_REPRODUCED %s",id);
  endtask
  task automatic tick; @(posedge clk); #1; endtask
  logic [15:0] a=0,b=0,sum;
  logic sub=0,cout,ov;
  addsub ad(a,b,sub,cout,ov,sum);
  logic [15:0] ma[31:0],mb[31:0],mp[31:0],dq[31:0];
  logic mov;
  mul mu(ma,mb,mp,mov);
  div di(ma,mb,dq);
  logic [2:0] op=0;
  logic [15:0] rout[31:0];
  logic rc,ro;
  rowwise_op rowop(.a(ma),.b(mb),.select(op),.alu_out(rout),.carry_out(rc),.overflow(ro));
  logic [15:0] exa=0,exout;
  exp_row ex(exa,exout);
  localparam DW=`REVIEW_DATA_W;
  logic [DW*32-1:0] din='0,mout0,mout1;
  logic [2:0] ra0=0,ra1=0,wa=0;
  logic wen=0,ren0=0,ren1=0,typ=0,tmw=0,rf,wf,fe,af,ae;
  mem_mapping #(.DATA_WIDTH(DW),.MEM_DEPTH(`REVIEW_MEM_DEPTH)) mm(
    .clk(clk),.rst_n(rst_n),.data_in(din),.r_addr_0(ra0),.r_addr_1(ra1),.w_addr(wa),
    .w_en(wen),.rd_en_0(ren0),.rd_en_1(ren1),.rd_type(typ),.tmatmul_write(tmw),
    .read_finish(rf),.write_finish(wf),.fifo_1_empty(fe),.data_out_0(mout0),.data_out_1(mout1),
    .almost_full(af),.almost_empty(ae));
  logic [1:0] gra0=0,gra1=0,gwa=0;
  logic gwen=0,gren=0,gfull,gempty,gaf,gae;
  logic [DW*32-1:0] gout0,gout1;
  register #(.DATA_WIDTH(DW),.ADDR_WIDTH(`REVIEW_REG_ADDR_W),.MEM_DEPTH(`REVIEW_REG_DEPTH)) gr(
    .clk(clk),.rst_n(rst_n),.data_in(din),.r_addr_0(gra0),.r_addr_1(gra1),.w_addr(gwa),
    .w_en(gwen),.rd_en(gren),.full(gfull),.empty(gempty),.almost_full(gaf),.almost_empty(gae),
    .data_out_0(gout0),.data_out_1(gout1));
  localparam BW=`REVIEW_BURST_DATA_W, AW=`REVIEW_BURST_ADDR_W;
  logic brst=1,brreq=0,bwreq=0,ardy=0,wready=0,rv=0;
  logic [9:0] rlen=1,wlen=1;
  logic [AW-1:0] raddr=0,waddr=0,appaddr;
  wire [2:0] cmd;
  wire en,wend,wwren,wrreq,rfinish,wfinish,finish,rdvalid;
  wire [BW-1:0] rdata,wdata;
  mem_burst #(.MEM_DATA_BITS(BW),.ADDR_BITS(AW)) burst(
    .rst(brst),.mem_clk(clk),.rd_burst_req(brreq),.wr_burst_req(bwreq),
    .rd_burst_len(rlen),.wr_burst_len(wlen),.rd_burst_addr(raddr),.wr_burst_addr(waddr),
    .rd_burst_data_valid(rdvalid),.wr_burst_data_req(wrreq),.rd_burst_data(rdata),
    .wr_burst_data({BW{1'b1}}),.rd_burst_finish(rfinish),.wr_burst_finish(wfinish),.burst_finish(finish),
    .app_addr(appaddr),.app_cmd(cmd),.app_en(en),.app_wdf_data(wdata),.app_wdf_end(wend),
    .app_wdf_wren(wwren),.app_rd_data({BW{1'b0}}),.app_rd_data_end(1'b1),
    .app_rd_data_valid(rv),.app_rdy(ardy),.app_wdf_rdy(wready),
    .ui_clk_sync_rst(1'b0),.init_calib_complete(1'b1));
  initial begin
    for(int i=0;i<32;i++) begin ma[i]=0;mb[i]=1;end
    #1;
    a=5;b=3;sub=1; #1;
    $display("ADD_SUB select=1 a=5 b=3 actual=%h expected=0002",sum);
    evidence("F01 subtraction precedence",sum!==16'd2);
    ma[0]=16'h1000;mb[0]=16'h1000; #1;
    $display("MUL_Q4_12 1*1 actual=%h expected=1000",mp[0]);
    evidence("F03 multiply scale",mp[0]!==16'h1000);
    evidence("F04 divide scale (Q4.12 contract)",dq[0]!==16'h1000);
    ma[0]=16'hf000;mb[0]=16'h1000; #1;
    $display("MUL_Q4_12 -1*1 actual=%h overflow=%b",mp[0],mov);
    evidence("F03 negative false overflow",mov===1'b1 && mp[0]===16'hffff);
    op=3'b110; #1;
    evidence("F02 unrelated MUL overflow on SIG",ro===1'b1);
    ma[0]=5;mb[0]=3;op=3'b010; #1;
    $display("ROWWISE SUB 5-3 actual=%h expected=0002",rout[0]);
    evidence("F01 SUB opcode selects addition",rout[0]===16'd8);
    exa=0; #1;
    $display("EXP input=0 index=%0d output=%h",ex.y,exout);
    evidence("F05 EXP out-of-range",ex.y==32768 && $isunknown(exout));
    ma[0]=1;mb[0]=0; #1;
    evidence("F04 divide by zero propagates X",$isunknown(dq[0]));
    tick(); @(negedge clk); rst_n=1;brst=0;
    ra1=3; #1;
    $display("V_INDEX selector=3 actual=%0d expected=384",mm.v_index);
    evidence("F07 bank selector aliases",mm.v_index==0);
    evidence("F12 write_finish high while IDLE after reset",wf===1);
    // Normal 16-beat memory write, keep enable asserted throughout RUN.
    @(negedge clk); ra1=0;wa=1;din='1;wen=1;
    repeat(2) tick();
    repeat(16) tick();
    evidence("F08 last word omitted",mm.mem[30]=={DW*32{1'b1}} && mm.mem[31]==0);
    @(negedge clk);wen=0;
    repeat(2) tick();
    // RUN pointer moves even when memory write is disabled.
    @(negedge clk); wa=2;wen=1;
    repeat(2) tick();
    @(negedge clk);wen=0;
    tick();
    evidence("F09 pointer advances without write",mm.w_ptr==33 && mm.mem[32]==0);
    repeat(17) tick();
    // Read endpoints are live; change base while a burst is running.
    @(negedge clk);ra0=1;ren0=1;
    repeat(2) tick();
    @(negedge clk);ren0=0;ra0=2;
    #1;
    evidence("F10 active read endpoint changes with request",mm.r_ptr_0==16 && mm.r_ptr_0_end==47);
    // Register stream executes 16 beats at highest legal scaled selector.
    @(negedge clk);gwa=3;gwen=1;
    repeat(2) tick();
    @(negedge clk);gwen=0;
    repeat(16) tick();
    $display("SCALED_REG highest selector last word=%h",gr.mem[63]);
    evidence("F09 register continues after w_en deasserted (contract risk)",gr.mem[63]=={DW*32{1'b1}});
    // DDR: command accepted before first data beat. END drops too early.
    @(negedge clk);bwreq=1;ardy=1;wready=0;wlen=1;
    tick(); @(negedge clk);bwreq=0;
    tick(); @(negedge clk);wready=1;
    tick();
    evidence("F17 accepted WDF beat without END",wwren===1 && wend===0);
    repeat(3) tick();
    // Address scaling aliases upper input bits.
    @(negedge clk);brst=1; tick();
    @(negedge clk);brst=0;brreq=1;raddr=8;rlen=1;ardy=0;
    tick();
    evidence("F18 burst address truncation",appaddr==0);
    // Length zero: after >1024 accepted commands, still in MEM_READ.
    @(negedge clk);brst=1;brreq=0; tick();
    @(negedge clk);brst=0;brreq=1;raddr=0;rlen=0;ardy=1;
    tick(); @(negedge clk);brreq=0;
    repeat(1030) tick();
    evidence("F16 zero length never completes",burst.state==1 && en===1 && rfinish===0);
    $display("EVIDENCE_SUMMARY reproduced=%0d checks=%0d (bug reproduction, not design PASS)",reproduced,checks);
    $finish;
  end
  initial begin #200000; $fatal(1,"watchdog"); end
endmodule
