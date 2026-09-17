`timescale 1ns/1ps
module tb_alu;
    parameter W=8;
    localparam F=W-4,LO=-(1<<(W-1)),HI=(1<<(W-1))-1,MASK=(1<<W)-1;
    logic [W-1:0] a[31:0],b[31:0],n[31:0],result[31:0];
    logic [2:0] op;
    logic carry,overflow,nv=0;
    logic [W-1:0] exp_lut[0:(1<<W)-1],sig_lut[0:(1<<W)-1];
    rowwise_op #(.DATA_WIDTH(W),.FRAC_WIDTH(F),
        .EXP_INIT_FILE(W==8 ? "functional/assets/exp_8.hex" : "functional/assets/exp_16.hex"),
        .SIG_INIT_FILE(W==8 ? "functional/assets/sig_8.bin" : "functional/assets/sig_16.bin")
    ) dut(.a(a),.b(b),.norm_result(n),.norm_overflow(nv),.select(op),.alu_out(result),.carry_out(carry),.overflow(overflow));
    function automatic longint signed clamp(input longint signed x);
        return x>HI ? HI : x<LO ? LO : x;
    endfunction
    integer checks=0;
    initial begin
        $readmemh(W==8 ? "functional/assets/exp_8.hex" : "functional/assets/exp_16.hex",exp_lut);
        $readmemb(W==8 ? "functional/assets/sig_8.bin" : "functional/assets/sig_16.bin",sig_lut);
        for(int batch=0;batch<(W==8 ? 2048 : 1024);batch++) begin
            for(int lane=0;lane<32;lane++) begin
                if(W==8) begin a[lane]=W'((batch*32+lane)>>8); b[lane]=W'(batch*32+lane); end
                else begin
                    a[lane]=W'((batch*32+lane)*7919+32768);
                    b[lane]=W'((batch*32+lane)*9973);
                    if(batch<8) begin a[lane]=W'(LO+batch); b[lane]=W'(lane-16); end
                end
                n[lane]=W'(lane);
            end
            for(int select_op=0;select_op<8;select_op++) begin : compare_operation
                bit cf,vf;
                longint signed x,y,z,expected;
                op=3'(select_op); nv=select_op==7;
                #1;
                cf=0;vf=0;
                for(int lane=0;lane<32;lane++) begin
                    x=$signed(a[lane]); y=$signed(b[lane]); z=0; expected=0;
                    case(select_op)
                        1: begin z=x+y; cf|=(int'(a[lane])+int'(b[lane])>MASK); end
                        2: begin z=x-y; cf|=(a[lane]<b[lane]); end
                        3: z=(x*y)>>>F;
                        4: begin
                            if(y==0) begin z=x==0 ? 0 : x<0 ? LO : HI; vf=1; end
                            else z=(x*(1<<F))/y;
                        end
                        5: begin z=exp_lut[int'(a[lane])^(1<<(W-1))]; vf|=x>=(W==8 ? 34 : 8518); end
                        6: z=sig_lut[int'(a[lane])^(1<<(W-1))];
                        7: begin z=lane; vf=1; end
                        default: z=0;
                    endcase
                    if(select_op>=1 && select_op<=4) vf|=(z>HI || z<LO);
                    expected=clamp(z);
                    if(result[lane]!==W'(expected))
                        $fatal(1,"ALU W=%0d op=%0d a=%0d b=%0d got=%h exp=%h",W,select_op,x,y,result[lane],W'(expected));
                    checks++;
                end
                if(carry!==cf || overflow!==vf) $fatal(1,"ALU flags W=%0d op=%0d",W,select_op);
            end
        end
        $display("ALU_PASS W=%0d comparisons=%0d",W,checks); $finish;
    end
endmodule
