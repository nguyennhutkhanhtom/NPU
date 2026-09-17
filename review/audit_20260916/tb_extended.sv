`timescale 1ns/1ps
module tb_extended;
  logic clk=0; always #5 clk=~clk;
  logic rst_n=0;
  int checks=0, reproduced=0;
  task automatic check(input string id, input bit observed);
    checks++;
    if(observed) begin reproduced++; $display("REPRODUCED %s",id); end
    else $display("NOT_REPRODUCED %s",id);
  endtask
  task automatic tick; @(posedge clk); #1; endtask
  logic [15:0] a[31:0],b[31:0],out[31:0];
  logic [2:0] op=0; logic carry,ov;
  rowwise_op alu(a,b,op,out,carry,ov);
  logic [15:0] terms[511:0],sum;
  acc_mul acc(terms,sum);
  logic [12:0] fd=0,de=0,em=0,mw=0;
  logic read_done=0,write_done=0,empty=1,full=0,rd=0,wr=0,tm=0,ae=0,af=0;
  logic es,ms,fs,ds,ps,flush;
  hazard_detect hz(.clk(clk),.rst_n(rst_n),.instr_fd(fd),.instr_de(de),.instr_em(em),.instr_mw(mw),
    .read_finish(read_done),.write_finish(write_done),.empty(empty),.full(full),.rd_en(rd),.wr_en(wr),
    .tmatmul_assert(tm),.almost_empty(ae),.almost_full(af),.em_stall(es),.mw_stall(ms),.fd_stall(fs),
    .de_stall(ds),.pc_stall(ps),.flush_wb(flush));
  logic [12:0] ci=0; logic crw,crr,cmw,cmr0,cmr1,csel; logic [2:0] cop;
  ctrl_unit ctrl(ci,crw,crr,cop,cmw,cmr0,cmr1,csel);
  logic [127:0] din='1,dout0,dout1;
  logic [2:0] ra0=0,ra1=0,wa=0; logic wen=0,ren0=0,ren1=0,typ=0,tmw=0;
  logic rf,wf,fe,maf,mae;
  mem_mapping #(.DATA_WIDTH(4),.MEM_DEPTH(8192)) mm(
    .clk(clk),.rst_n(rst_n),.data_in(din),.r_addr_0(ra0),.r_addr_1(ra1),.w_addr(wa),
    .w_en(wen),.rd_en_0(ren0),.rd_en_1(ren1),.rd_type(typ),.tmatmul_write(tmw),
    .read_finish(rf),.write_finish(wf),.fifo_1_empty(fe),.data_out_0(dout0),.data_out_1(dout1),
    .almost_full(maf),.almost_empty(mae));
  logic brst=1,brreq=0,bwreq=0,ardy=0,wready=0,rv=0,uireset=0,cal=1;
  logic [9:0] rlen=1,wlen=1;
  logic [5:0] raddr=0,waddr=0,appaddr; wire [2:0] cmd;
  wire en,wend,wwren,wrreq,rfinish,wfinish,finish,rdvalid;
  wire [31:0] rdata,wdata;
  mem_burst #(.MEM_DATA_BITS(32),.ADDR_BITS(6)) burst(
    .rst(brst),.mem_clk(clk),.rd_burst_req(brreq),.wr_burst_req(bwreq),.rd_burst_len(rlen),.wr_burst_len(wlen),
    .rd_burst_addr(raddr),.wr_burst_addr(waddr),.rd_burst_data_valid(rdvalid),.wr_burst_data_req(wrreq),
    .rd_burst_data(rdata),.wr_burst_data(32'h1234),.rd_burst_finish(rfinish),.wr_burst_finish(wfinish),
    .burst_finish(finish),.app_addr(appaddr),.app_cmd(cmd),.app_en(en),.app_wdf_data(wdata),.app_wdf_end(wend),
    .app_wdf_wren(wwren),.app_rd_data(32'b0),.app_rd_data_end(1'b1),.app_rd_data_valid(rv),
    .app_rdy(ardy),.app_wdf_rdy(wready),.ui_clk_sync_rst(uireset),.init_calib_complete(cal));
  // Exact HALT expression used at matmulfree.sv:309, tested independently.
  logic [12:0] halt_word; wire ready_expr=&halt_word;
  initial begin
    for(int i=0;i<32;i++) begin a[i]=0;b[i]=1;end
    for(int i=0;i<512;i++) terms[i]=0;
    a[0]=16'h1000;op=7; #1;
    check("F06 NORM returns zero for nonzero input",out[0]===0);
    a[0]=16'h8000;b[0]=16'hffff;op=4; #1;
    check("F04 signed division min/-1 wraps",out[0]===16'h8000);
    terms[0]=16'h7fff;terms[1]=1; #1;
    check("F15 accumulator 32767+1 wraps to negative",sum===16'h8000);
    for(int i=0;i<512;i++) terms[i]=16'h1000;
    #1; check("F15 512 Q4.12 ones accumulate to zero",sum===0);
    for(int i=0;i<32;i++) begin a[i]=0;b[i]=0;end
    a[0]=16'hffff;b[0]=1;op=2; #1;
    check("F02 SUB carry suppressed",carry===0 && alu.cout[0]===1);
    op=6; #1;
    check("F02 SIG exposes ADD carry",carry===1);
    halt_word=13'b1111_000_000_000; #1;
    check("F23 HALT opcode alone does not assert ready",ready_expr===0);
    tick(); @(negedge clk); rst_n=1;brst=0;
    // Independent truth-table checks: the status flags do not encode RAW dependencies.
    de=13'b0001_010_000_001;em=13'b1001_001_000_000;rd=1;ae=1; #1;
    check("F22 RAW dependency not detected when almost_empty high",hz.hazard_1===0 && ds===1);
    em=13'b1000_011_001_010;tm=1; #1;
    check("F22 second TMATMUL does not set memory hazard",hz.hazard_0===0 && es===1);
    em=13'b1001_010_000_001;read_done=1; #1;
    check("F22 LDV released at read completion before TM write completion",hz.hazard_0===0);
    check("F22 same LDV still asserts WB flush",flush===1);
    tm=0;de=0;rd=0;em=13'b1010_001_000_010;tick();
    check("F22 write hazard excludes STV",hz.hazard_2===0);
    // Unknown opcode is incorrectly accepted as LDV by casex.
    ci='x; #1;
    check("F24 unknown opcode enables load/writeback",crw===1 && cmr0===1);
    // In TMATMUL mode write strobe ignores the result-valid gate.
    @(negedge clk);typ=1;wa=2;wen=1;tmw=0;
    repeat(3) tick();
    check("F09 memory written before tmatmul_write",mm.mem[32]==='1 && mm.w_ptr==32);
    @(negedge clk);wen=0;rst_n=0;tick();
    // A single port1 request still streams port0 to its 1024-word endpoint.
    @(negedge clk);rst_n=1;ren1=1;ren0=0;ra0=7;
    repeat(2) tick(); @(negedge clk);ren1=0;tick();
    check("F11 port1-only request advances disabled port0",mm.r_ptr_0==7169 && mm.state_read==2);
    // Move endpoint behind live pointer. No completion until 19-bit wrap.
    @(negedge clk);typ=0;ra0=0;
    repeat(1100) tick();
    check("F10 live endpoint move leaves read running beyond scaled RAM",mm.state_read==2 && mm.r_ptr_0>8191);
    // UI reset is ignored while a command is pending.
    @(negedge clk);brreq=1;ardy=0;
    tick(); @(negedge clk);brreq=0;uireset=1;tick();
    check("F19 ui_clk_sync_rst ignored",burst.state==1 && en===1);
    @(negedge clk);uireset=0;cal=0;ardy=1;tick();
    check("F19 calibration loss holds enabled command/address",en===1 && appaddr===0 && burst.rd_addr_cnt===0);
    @(negedge clk);brst=1;cal=1;ardy=0;tick();
    // Caller changes length after command request. Transaction ends at new length.
    @(negedge clk);brst=0;brreq=1;rlen=3;tick();
    @(negedge clk);brreq=0;rlen=1;ardy=1;tick();
    check("F16 burst length is not latched",burst.state==2 && en===0);
    @(negedge clk);brst=1;ardy=0;tick();
    @(negedge clk);brst=0;bwreq=1;wlen=0;wready=1;ardy=1;tick();
    @(negedge clk);bwreq=0;repeat(1030) tick();
    check("F16 zero write length never completes",burst.state==3 && wfinish===0);
    $display("EXTENDED_SUMMARY reproduced=%0d checks=%0d",reproduced,checks);
    if(reproduced!=checks) $fatal(1,"Evidence mismatch");
    $finish;
  end
  initial begin #100000; $fatal(1,"watchdog"); end
endmodule
