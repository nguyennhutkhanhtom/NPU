`timescale 1ns/1ps
module tb_ternary;
    parameter int W=16, L=32, R=512, C=512, D=32, G=8, SAT=0;
    localparam int WW=W*L, PER=WW/2, MW=(R*C+PER-1)/PER, VW=C/L, OW=(R+L-1)/L;
    localparam longint signed LO=-(64'sd1 << (W-1)), HI=(64'sd1 << (W-1))-1;
    logic clk=0,rst_n=0,start=0,av=0,tv=0,ordy=0;
    logic [WW-1:0] activation,weights,result,held;
    wire ardy,trdy,valid,busy,done,overflow;
    int checks=0, rows=0, cycles=0;
    always #5 clk=~clk;
    ternary_mul #(.DATA_WIDTH(W),.LANES(L),.MATRIX_ROWS(R),.MATRIX_COLS(C),
        .DOT_LANES(D),.REDUCE_GROUP(G),.SATURATE(SAT)) dut (
        .clk(clk),.rst_n(rst_n),.enable(start),.matrix_in(activation),.ternary_matrix(weights),
        .matrix_valid(av),.ternary_valid(tv),.output_ready(ordy),.matrix_ready(ardy),.ternary_ready(trdy),
        .matrix_out(result),.tmatmul_write(valid),.busy(busy),.done(done),.overflow(overflow));

    function automatic longint signed sample(input int test,input int col);
        logic signed [W-1:0] value;
        case(test)
            0: value=W'(col%31-15);
            1,4,7: value=W'(LO);
            8: value=W'(HI);
            2: value=W'(col%7-3);
            3: value=col%2 ? W'(LO) : W'(HI);
            default: value=W'((64'h134579adebc91827*(col+3)) ^ (64'h712987754983*(col+1)));
        endcase
        return $signed(value);
    endfunction
    function automatic logic [1:0] code(input int test,input int row,input int col);
        case(test)
            0: return row%C==col ? 2'b01 : 2'b00;
            1: return 2'b11;
            2: return col==(row+C-1)%C ? 2'b11 : col==(row+17)%C ? 2'b01 : 2'b00;
            3,7,8: return 2'b01;
            4: return col%2 ? 2'b11 : 2'b01;
            5: return 2'b10;
            default: return 2'(((row*137+col*73+17) ^ ((col*31+row*19)>>3)) % 4);
        endcase
    endfunction
    function automatic longint signed total(input int test,input int row);
        longint signed sum;
        sum=0;
        for(int col=0;col<C;col++) begin
            case(code(test,row,col))
                2'b01: sum+=sample(test,col);
                2'b11: sum-=sample(test,col);
                default: sum+=0;
            endcase
        end
        return sum;
    endfunction

    task automatic reset_dut;
        @(negedge clk);rst_n=0;av=0;tv=0;ordy=0;start=0;
        repeat(2) @(negedge clk);
        if(busy || valid || done || ardy || trdy) $fatal(1,"Control not reset");
        rst_n=1;
    endtask

    // abort=1 during capture, 2 with products in flight, 3 during held output.
    task automatic frame(input int test,input int abort);
        int ca,ct,cw,ticks,computed,stalls;
        bit holding,held_overflow,expected_overflow;
        longint signed expected,exact;
        @(negedge clk);start=1;
        @(negedge clk);start=0;
        ca=0;ct=0;cw=0;ticks=0;computed=0;stalls=0;holding=0;
        while(1) begin
            // Sources must retain VALID and data until their handshake.
            if(!av || ardy) begin
                av=ca<VW && (ticks%5!=0 || test==0);
                for(int lane=0;lane<L;lane++) activation[lane*W+:W]=W'(sample(test,ca*L+lane));
            end
            if(!tv || trdy) begin
                tv=ct<MW && (ticks%7!=0 || test==0);
                for(int k=0;k<PER;k++) weights[k*2+:2]=code(test,(ct*PER+k)/C,(ct*PER+k)%C);
            end
            ordy=abort!=3 && ticks%11>=4;
            // Starts while busy are ignored; descriptors/data already accepted survive.
            start=(ticks==23);
            @(posedge clk);
            if(av && ardy) ca++;
            if(tv && trdy) ct++;
            if(dut.result_valid) begin
                if($signed(dut.row_result)!==total(test,computed))
                    $fatal(1,"Exact row W=%0d test=%0d row=%0d got=%0d expected=%0d",W,test,computed,$signed(dut.row_result),total(test,computed));
                computed++;rows++;
            end
            if(holding && (!valid || result!==held || overflow!==held_overflow)) $fatal(1,"Stalled output changed");
            if(valid && ordy) begin
                expected_overflow=0;
                for(int lane=0;lane<L;lane++) begin
                    exact=cw*L+lane<R ? total(test,cw*L+lane) : 0;
                    expected_overflow|=exact>HI || exact<LO;
                    expected=SAT && exact>HI ? HI : SAT && exact<LO ? LO : exact;
                    if(cw>=OW || result[lane*W+:W]!==W'(expected))
                        $fatal(1,"Output W=%0d test=%0d row=%0d got=%h expected=%h",W,test,cw*L+lane,result[lane*W+:W],W'(expected));
                    checks++;
                end
                if(overflow!==expected_overflow) $fatal(1,"Overflow mismatch");
                cw++;
            end
            holding=valid&&!ordy;held=result;held_overflow=overflow;
            if(holding) stalls++;
            #1;ticks++;cycles++;
            if(done) begin
                if(busy || valid || ca!=VW || ct!=MW || cw!=OW || computed!=R) $fatal(1,"Frame counts/done mismatch");
                break;
            end
            if((abort==1 && ca>0) || (abort==2 && dut.group_valid) || (abort==3 && stalls==7)) begin
                reset_dut();return;
            end
            if(ticks>MW*32+R*(C/D+20)+1000) $fatal(1,"Frame watchdog");
            @(negedge clk);
        end
        @(negedge clk);av=0;tv=0;ordy=0;start=0;
        @(negedge clk);if(done || valid) $fatal(1,"Done not a single pulse");
    endtask

    initial begin
        reset_dut();
        frame(0,1);frame(6,2);frame(2,3);
        for(int test=0;test<9;test++) frame(test,0);
        $display("TERNARY_PASS W=%0d L=%0d R=%0d C=%0d D=%0d G=%0d SAT=%0d checks=%0d rows=%0d cycles=%0d",W,L,R,C,D,G,SAT,checks,rows,cycles);
        $finish;
    end
endmodule
