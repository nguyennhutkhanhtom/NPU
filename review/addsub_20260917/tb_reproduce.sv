`timescale 1ns/1ps
module tb_reproduce;
    parameter EXPECT_BUGS=0;
    logic [15:0] a=5,b=3,result;
    logic sub=1,carry,overflow;
    logic [15:0] va[31:0],vb[31:0],vr[31:0];
    logic [2:0] op=1;
    logic vc,vv;
    int bugs=0;
    addsub leaf(a,b,sub,carry,overflow,result);
    rowwise_op row(.a(va),.b(vb),.select(op),.alu_out(vr),.carry_out(vc),.overflow(vv));
    initial begin
        for(int i=0;i<32;i++) begin va[i]=5;vb[i]=3;end
        #1;
        if(result!==16'd2) bugs++;
        $display("DIRECT_SUB 5-3=%h",result);
        if(vr[0]!==16'd8 || vc!==0 || vv!==0) bugs++;
        $display("ROW_ADD 5+3=%h carry=%b overflow=%b",vr[0],vc,vv);
        op=2; #1;
        if(vr[0]!==16'd2 || vc!==0 || vv!==0) bugs++;
        $display("ROW_SUB 5-3=%h carry=%b overflow=%b",vr[0],vc,vv);
        // Inactive multiplier's negative-product flag must not contaminate SUB.
        for(int i=0;i<32;i++) begin va[i]=16'hffff;vb[i]=1;end
        #1;
        if(vr[0]!==16'hfffe || vc!==0 || vv!==0) bugs++;
        $display("ROW_SUB -1-1=%h carry=%b overflow=%b",vr[0],vc,vv);
        op=6; #1;
        if(vc!==0 || vv!==0) bugs++;
        if(EXPECT_BUGS && bugs!=4) $fatal(1,"Expected four failing baseline observations; got %0d",bugs);
        if(!EXPECT_BUGS && bugs!=0) $fatal(1,"Unfixed observations: %0d",bugs);
        $display("REPRO_PASS EXPECT_BUGS=%0d bugs=%0d",EXPECT_BUGS,bugs);
        $finish;
    end
endmodule
