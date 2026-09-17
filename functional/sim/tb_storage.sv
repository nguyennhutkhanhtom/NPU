`timescale 1ns/1ps
module tb_storage;
    parameter W=8;
    localparam WW=32*W,MW=(512*512*2)/WW,DEPTH=1024+8*MW;
    logic clk=0,rst_n=0;
    always #5 clk=~clk;
    logic [WW-1:0] mi,mo0,mo1,ri,ro0,ro1;
    logic [2:0] ma0=0,ma1=0,mwa=0;
    logic mwe=0,mre0=0,mre1=0,mt=0,mtw=0,mwv=0,mrr0=0,mrr1=0;
    wire mready,mv0,mv1,mrdone,mwdone,mp1done,maf,mae;
    mem_mapping #(.DATA_WIDTH(W),.MEM_DEPTH(DEPTH),.INIT_FILE("")) ram(
        .clk(clk),.rst_n(rst_n),.data_in(mi),.r_addr_0(ma0),.r_addr_1(ma1),.w_addr(mwa),
        .w_en(mwe),.rd_en_0(mre0),.rd_en_1(mre1),.rd_type(mt),.tmatmul_write(mtw),
        .write_valid(mwv),.read_ready_0(mrr0),.read_ready_1(mrr1),.write_ready(mready),
        .read_valid_0(mv0),.read_valid_1(mv1),.read_finish(mrdone),.write_finish(mwdone),
        .fifo_1_empty(mp1done),.data_out_0(mo0),.data_out_1(mo1),.almost_full(maf),.almost_empty(mae));
    logic [3:0] ra0=0,ra1=0,rwa=0;
    logic rwe=0,rre=0,rwv=0,rrr=0;
    wire rrdy,rv,rfull,rempty,raf,rae;
    register #(.DATA_WIDTH(W),.ADDR_WIDTH(4),.MEM_DEPTH(257)) rf(
        .clk(clk),.rst_n(rst_n),.data_in(ri),.r_addr_0(ra0),.r_addr_1(ra1),.w_addr(rwa),
        .w_en(rwe),.rd_en(rre),.write_valid(rwv),.read_ready(rrr),.write_ready(rrdy),
        .read_valid(rv),.full(rfull),.empty(rempty),.data_out_0(ro0),.data_out_1(ro1),
        .almost_full(raf),.almost_empty(rae));
    function automatic [WW-1:0] pattern(input int tag,input int index);
        for(int lane=0;lane<32;lane++) pattern[lane*W+:W]=W'(tag*31+index*7+lane);
    endfunction
    task automatic memory_write(input int bank,input int dest,input bit ternary_mode);
        int j,ticks,base;
        base=(ternary_mode ? 0 : bank*128)+dest*16;
        @(negedge clk); ma1=3'(bank); mwa=3'(dest); mt=ternary_mode; mwe=1;
        @(negedge clk); mwe=0;
        wait(mready); j=0;ticks=0;
        while(j<16) begin
            @(negedge clk);
            ma1=3'(ticks); mwa=3'(ticks+1); mt=!ternary_mode;
            mwv=ticks%3!=0; mtw=ticks%4!=0; mi=pattern(9,j);
            @(posedge clk);
            if(mwv && (!ternary_mode || mtw)) begin
                #1;
                if(ram.mem[base+j]!==pattern(9,j)) $fatal(1,"RAM accepted word %0d",j);
                if(mwdone!==(j==15)) $fatal(1,"RAM premature/missing write done");
                j++;
            end else begin #1; if(mwdone) $fatal(1,"RAM done during bubble"); end
            ticks++;
        end
        @(negedge clk);mwv=0;mtw=0;
        @(negedge clk);if(mwdone) $fatal(1,"RAM done not pulse");
        for(int k=0;k<16;k++) if(ram.mem[base+k]!==pattern(9,k)) $fatal(1,"RAM last/overwrite");
    endtask
    task automatic memory_read(input bit mode,input bit port0,input bit port1,input int a0,input int a1);
        int n0,n1,base0,base1,c0,c1,ticks;
        logic [WW-1:0] held0,held1;
        bit hold0,hold1;
        n0=port0 ? (mode ? MW : 16) : 0; n1=port1 ? 16 : 0;
        base0=mode ? 1024+a0*MW : a1*128+a0*16; base1=a1*16;
        c0=0;c1=0;ticks=0;hold0=0;hold1=0;
        @(negedge clk); mt=mode;ma0=3'(a0);ma1=3'(a1);mre0=port0;mre1=port1;
        @(negedge clk); mre0=0;mre1=0;
        while(!mrdone) begin
            @(negedge clk); mt=!mode;ma0=3'(ticks);ma1=3'(ticks+3);
            mrr0=ticks%3!=0;mrr1=ticks%4!=0;
            @(posedge clk);
            if(hold0 && mo0!==held0) $fatal(1,"RAM read0 not stable under stall");
            if(hold1 && mo1!==held1) $fatal(1,"RAM read1 not stable under stall");
            if(!port0 && mv0) $fatal(1,"Disabled read port0 became valid");
            if(!port1 && mv1) $fatal(1,"Disabled read port1 became valid");
            if(mv0 && mrr0) begin
                if(c0>=n0 || mo0!==ram.mem[base0+c0]) $fatal(1,"RAM read0 descriptor/count %0d",c0);
                c0++;
            end
            if(mv1 && mrr1) begin
                if(c1>=n1 || mo1!==ram.mem[base1+c1]) $fatal(1,"RAM read1 descriptor/count %0d",c1);
                c1++;
            end
            hold0=mv0&&!mrr0;held0=mo0;hold1=mv1&&!mrr1;held1=mo1;
            #1;ticks++;
            if(ticks>MW*3) $fatal(1,"RAM read timeout");
        end
        if(c0!=n0 || c1!=n1) $fatal(1,"RAM dropped final read");
        @(negedge clk);mrr0=0;mrr1=0;
        @(negedge clk);if(mrdone || mv0 || mv1) $fatal(1,"RAM idle status");
    endtask
    initial begin : run_tests
        int count,ticks;
        for(int i=0;i<DEPTH;i++) ram.mem[i]=pattern(1,i);
        for(int i=0;i<257;i++) rf.mem[i]=pattern(2,i);
        repeat(3) @(negedge clk);rst_n=1;
        if(mrdone || mwdone || rfull || rempty) $fatal(1,"Spurious reset completion");
        memory_write(7,7,0);
        memory_write(3,2,0);
        memory_write(0,4,1);
        memory_read(0,1,0,7,7);
        memory_read(1,0,1,7,3);
        memory_read(1,1,1,7,2);
        @(negedge clk);rwa=15;rwe=1;
        @(negedge clk);rwe=0;
        wait(rrdy);count=0;ticks=0;
        while(count<16) begin
            @(negedge clk);rwa=4'(ticks);rwv=ticks%3!=0;ri=pattern(7,count);
            @(posedge clk);
            if(rwv) begin #1;
                if(rf.mem[240+count]!==pattern(7,count) || rfull!==(count==15))
                    $fatal(1,"Register write last/count");
                count++;
            end
            ticks++;
        end
        @(negedge clk);rwv=0;ra0=15;ra1=14;rre=1;
        @(negedge clk);rre=0;
        count=0;ticks=0;
        while(!rempty) begin
            @(negedge clk);ra0=4'(ticks);ra1=4'(ticks+1);rrr=ticks%4!=0;
            @(posedge clk);
            if(rv && rrr) begin
                if(ro0!==pattern(7,count) || ro1!==pattern(2,224+count)) $fatal(1,"Register read descriptor");
                count++;
            end
            #1;ticks++;
        end
        if(count!=16) $fatal(1,"Register read count");
        // Abort both resources with valid asserted: no write may occur in reset.
        @(negedge clk);rrr=0;mt=0;ma1=0;mwa=1;mwe=1;rwa=1;rwe=1;mre0=1;rre=1;
        @(negedge clk);mwe=0;rwe=0;mre0=0;rre=0;
        wait(mready && rrdy);
        @(negedge clk);rst_n=0;mwv=1;rwv=1;mi='1;ri='1;
        repeat(3) @(negedge clk);
        if(mready || rrdy || mv0 || rv || mwdone || rfull) $fatal(1,"Reset left active handshake");
        if(ram.mem[16]!==pattern(1,16) || rf.mem[16]!==pattern(2,16)) $fatal(1,"Write during reset");
        mwv=0;rwv=0;rst_n=1;
        repeat(3) @(negedge clk);
        if(mready || rrdy || mv0 || rv) $fatal(1,"Aborted transaction resumed");
        $display("STORAGE_PASS W=%0d exact_depth=%0d",W,DEPTH);$finish;
    end
    initial begin #300000;$fatal(1,"STORAGE watchdog");end
endmodule
