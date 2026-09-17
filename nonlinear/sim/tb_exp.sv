`timescale 1ns/1ps
module tb_exp;
    parameter W=16,A=(W==8?8:9);
    logic [W-1:0] a,result;
    wire ov,uf;
    logic [W-1:0] expected[0:(1<<W)-1],exact[0:(1<<W)-1];
    int maximum_error=0,previous=-1;
    exp_row #(.DATA_WIDTH(W),.LUT_ADDR_BITS(A)) dut(a,result,ov,uf);
    initial begin
        $readmemh($sformatf("nonlinear/assets/exp_expected_%0d_%0d.hex",W,A),expected);
        $readmemh($sformatf("nonlinear/assets/exp_exact_%0d.hex",W),exact);
        for(int i=0;i<(1<<W);i++) begin
            a=W'(i-(1<<(W-1))); #1;
            if(result!==expected[i] || ov!==($signed(a)>=(W==8?34:8518)) || uf!==(result==0))
                $fatal(1,"EXP W=%0d A=%0d raw=%0d got=%h expected=%h ov=%b uf=%b",W,A,$signed(a),result,expected[i],ov,uf);
            if(int'(result)<previous) $fatal(1,"EXP not monotonic");
            previous=int'(result);
            if(int'(result)>int'(exact[i])) begin
                if(int'(result)-int'(exact[i])>maximum_error) maximum_error=int'(result)-int'(exact[i]);
            end else if(int'(exact[i])-int'(result)>maximum_error) maximum_error=int'(exact[i])-int'(result);
        end
        $display("EXP_PASS W=%0d A=%0d inputs=%0d max_error_lsb=%0d",W,A,1<<W,maximum_error);$finish;
    end
endmodule
