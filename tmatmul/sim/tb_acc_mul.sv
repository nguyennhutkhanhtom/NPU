`timescale 1ns/1ps
module tb_acc_mul;
    parameter int W=16, N=512, A=W+$clog2(N);
    logic [W-1:0] terms [N-1:0];
    wire [A-1:0] result,sum,carry;
    longint signed expected;
    acc_mul #(.DATA_WIDTH(W),.NUM_INPUTS(N),.ACC_WIDTH(A)) dut (
        .mul_result(terms),.acc_result(result),.acc_sum(sum),.acc_carry(carry));
    initial begin
        for(int test=0;test<1000;test++) begin
            expected=0;
            for(int i=0;i<N;i++) begin
                case(test)
                    0: terms[i]='0;
                    1: terms[i]={1'b1,{(W-1){1'b0}}};
                    2: terms[i]={1'b0,{(W-1){1'b1}}};
                    3: terms[i]=i%2 ? '1 : W'(1);
                    default: terms[i]=W'({$urandom,$urandom});
                endcase
                expected+=$signed(terms[i]);
            end
            #1;
            if(result!==A'(expected) || A'(sum+carry)!==A'(expected))
                $fatal(1,"Accumulator W=%0d N=%0d A=%0d test=%0d got=%h expected=%h",W,N,A,test,result,A'(expected));
        end
        $display("ACC_PASS W=%0d N=%0d A=%0d cases=1000",W,N,A);$finish;
    end
endmodule
