`timescale 1ns/1ps
module tb_dispatch;
    parameter W=8;
    localparam WW=32*W,DEPTH=128,PW=7;
    logic clk=0,rst_n=0,pipeline_idle=0;
    logic [12:0] instruction=0;
    wire hold_front,advance,own,wen,done,overflow;
    wire [12:0] active;
    wire [PW-1:0] raddr,waddr;
    wire [WW-1:0] rd,wd,exp_data,unused_read;
    wire [31:0] exp_flags;
    wire f,e,af,ae,rb,wb;
    logic [WW-1:0] initial_words[0:15],expected[0:95];
    logic expected_flags[0:5];
    logic [12:0] program_words[0:63];
    int writes=0;
    always #5 clk=~clk;
    nonlinear_dispatch #(.DATA_WIDTH(W),.REG_DEPTH(DEPTH)) dut(
      .clk(clk),.rst_n(rst_n),.instruction(instruction),.pipeline_idle(pipeline_idle),
      .hold_front(hold_front),.advance_pc(advance),.own_register(own),
      .read_address(raddr),.write_address(waddr),.read_data(rd),.exp_data(exp_data),.exp_overflow(|exp_flags),
      .write_data(wd),.write_enable(wen),.done(done),.overflow(overflow),.active_instruction(active));
    register #(.DATA_WIDTH(W),.MEM_DEPTH(DEPTH),.ENABLE_NL_PORT(1)) rf(
      .clk(clk),.rst_n(rst_n),.data_in({WW{1'b0}}),.r_addr_0(3'b0),.r_addr_1(3'b0),.w_addr(3'b0),
      .w_en(1'b0),.rd_en(1'b0),.full(f),.empty(e),.almost_full(af),.almost_empty(ae),
      .data_out_0(rd),.data_out_1(unused_read),.nl_own(own),.nl_write(wen),
      .nl_raddr(raddr),.nl_waddr(waddr),.nl_data(wd),.read_busy(rb),.write_busy(wb));
    for(genvar i=0;i<32;i++) begin : ex
        exp_row #(.DATA_WIDTH(W)) lane(.a(rd[W*i +: W]),.result(exp_data[W*i +: W]),.overflow(exp_flags[i]),.underflow());
    end
    initial begin : test
        int count,cycles,dest;
        $readmemh($sformatf("nonlinear/assets/dispatch_initial_%0d.hex",W),initial_words);
        $readmemh($sformatf("nonlinear/assets/dispatch_expected_%0d.hex",W),expected);
        $readmemh($sformatf("nonlinear/assets/dispatch_flags_%0d.hex",W),expected_flags);
        $readmemb($sformatf("nonlinear/assets/dispatch_program_%0d.mem",W),program_words);
        repeat(3) @(negedge clk);
        for(int i=0;i<DEPTH;i++) rf.mem[i]='0;
        for(int i=0;i<16;i++) rf.mem[i]=initial_words[i];
        rst_n=1;
        for(int test=0;test<6;test++) begin
            @(negedge clk);instruction=program_words[test];pipeline_idle=0;
            repeat(5) begin @(posedge clk);#1;if(own||wen||done) $fatal(1,"Ownership before drain");end
            @(negedge clk);pipeline_idle=1;count=0;cycles=0;dest=int'(program_words[test][8:6])*16;
            // Changing live instruction after issue must not change source/dest/op.
            instruction=13'b0000_111_111_111;
            while(!done) begin
                @(posedge clk);
                if(wen) begin
                    if(waddr!==PW'(dest+count) || wd!==expected[test*16+count])
                      $fatal(1,"DISPATCH W=%0d test=%0d beat=%0d addr=%0d got=%h exp=%h",W,test,count,waddr,wd,expected[test*16+count]);
                    count++;writes++;
                end
                #1;cycles++;
                if(cycles>40000) $fatal(1,"Dispatch deadlock");
            end
            if(count!=16 || overflow!==expected_flags[test] || !advance || active!==program_words[test])
                $fatal(1,"Dispatch completion/flags");
            for(int i=0;i<16;i++) if(rf.mem[dest+i]!==expected[test*16+i]) $fatal(1,"Register commit mismatch");
            @(negedge clk);instruction=0;
            @(posedge clk);#1;if(done || own || advance) $fatal(1,"Repeated retirement");
        end
        $display("DISPATCH_PASS W=%0d instructions=6 accepted_writes=%0d in_place=1 latched_context=1",W,writes);$finish;
    end
    initial begin #5000000;$fatal(1,"Dispatch watchdog");end
endmodule
