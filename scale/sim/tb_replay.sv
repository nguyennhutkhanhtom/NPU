`timescale 1ns/1ps
// Compiled identically against baseline and parameterized libraries.
module tb_replay;
    logic clk=0; always #5 clk=~clk;
    logic rst_n=0;
    logic [15:0] a[31:0],b[31:0],out[31:0];
    logic [2:0] op=0; wire c,v;
    rowwise_op alu(a,b,op,out,c,v);
    logic [511:0] din='0,reg0,reg1,mem0,mem1;
    logic [2:0] ra0=0,ra1=0,wa=0;
    logic rw=0,rr=0,mw=0,mr=0,typ=0,tmw=0;
    wire full,empty,af,ae,rf,wf,fe,maf,mae;
    register regs(.clk(clk),.rst_n(rst_n),.data_in(din),.r_addr_0(ra0),.r_addr_1(ra1),.w_addr(wa),
        .w_en(rw),.rd_en(rr),.full(full),.empty(empty),.almost_full(af),.almost_empty(ae),.data_out_0(reg0),.data_out_1(reg1));
    mem_mapping ram(.clk(clk),.rst_n(rst_n),.data_in(din),.r_addr_0(ra0),.r_addr_1(ra1),.w_addr(wa),.w_en(mw),
        .rd_en_0(mr),.rd_en_1(mr),.rd_type(typ),.tmatmul_write(tmw),.read_finish(rf),.write_finish(wf),
        .fifo_1_empty(fe),.almost_full(maf),.almost_empty(mae),.data_out_0(mem0),.data_out_1(mem1));
    int f; string path;
    logic [31:0] rng=32'h193a64bc;
    logic [511:0] packed_out;
    task automatic random_step;
        rng=(rng<<1)^{32{rng[31]}}&32'h04c11db7;
    endtask
    initial begin
        if(!$value$plusargs("TRACE=%s",path)) path="trace.txt";
        f=$fopen(path,"w");
        for(int i=0;i<32;i++) begin a[i]=0;b[i]=0;end
        repeat(2) @(negedge clk);
        rst_n=1;
        for(int n=0;n<4096;n++) begin
            @(negedge clk);
            for(int lane=0;lane<32;lane++) begin
                random_step();a[lane]=rng[15:0];random_step();b[lane]=rng[15:0];
            end
            op=n%8;
            ra0=(n/40)%8;ra1=(n/80)%8;wa=(n/40)%8;
            rw=(n%40)<20;rr=(n%40)>=20;mw=rw;mr=rr;
            for(int lane=0;lane<32;lane++) din[lane*16+:16]=a[lane];
            #1;
            for(int lane=0;lane<32;lane++) packed_out[lane*16+:16]=out[lane];
            $fdisplay(f,"%0d %h %b%b %h %h %h %h %b%b%b%b%b%b%b%b%b",n,packed_out,c,v,reg0,reg1,mem0,mem1,full,empty,af,ae,rf,wf,fe,maf,mae);
        end
        $fclose(f);
        $display("REPLAY_DONE cycles=4096");$finish;
    end
endmodule
