`timescale 1ns/1ps
module tb_memory;
    parameter int W=16;
    localparam int WW=W*32, PER=WW/2, MW=(512*512+PER-1)/PER, DEPTH=1024+8*MW;
    logic clk=0,rst_n=0,start=0,mode=0;
    logic [2:0] matrix_addr=0,vector_addr=0,dest_addr=0;
    wire [WW-1:0] weights,activation,result;
    wire av,tv,ar,tr,wr,ready,done,rdone,wdone,busy;
    int writes=0,weight_reads=0,activation_reads=0;
    always #5 clk=~clk;
    mem_mapping #(.DATA_WIDTH(W),.MEM_DEPTH(DEPTH),.INIT_FILE("")) memory (
        .clk(clk),.rst_n(rst_n),.data_in(result),.r_addr_0(matrix_addr),.r_addr_1(vector_addr),.w_addr(dest_addr),
        .w_en(mode),.rd_en_0(mode),.rd_en_1(mode),.rd_type(mode),.tmatmul_write(wr),
        .read_finish(rdone),.write_finish(wdone),.fifo_1_empty(),.data_out_0(weights),.data_out_1(activation),
        .almost_full(),.almost_empty(),.matrix_ready(ar),.ternary_ready(tr),
        .matrix_valid(av),.ternary_valid(tv),.tmatmul_ready(ready));
    ternary_mul #(.DATA_WIDTH(W)) dut (.clk(clk),.rst_n(rst_n),.enable(start),
        .matrix_in(activation),.ternary_matrix(weights),.matrix_out(result),.tmatmul_write(wr),
        .matrix_valid(av),.ternary_valid(tv),.output_ready(ready),.matrix_ready(ar),.ternary_ready(tr),
        .busy(busy),.done(done),.overflow());
    function automatic logic [W-1:0] sample(input int col);
        return W'(col*17-2345);
    endfunction
    task automatic reset_dut;
        @(negedge clk);rst_n=0;mode=0;start=0;
        repeat(2) @(negedge clk);rst_n=1;
    endtask
    task automatic transaction(input int mat,input int src,input int dst,input bit abort);
        int ticks;
        @(negedge clk);matrix_addr=3'(mat);vector_addr=3'(src);dest_addr=3'(dst);mode=1;start=1;
        @(negedge clk);start=0;ticks=0;writes=0;weight_reads=0;activation_reads=0;
        while(!done) begin
            @(posedge clk);
            if(av && ar) activation_reads++;
            if(tv && tr) weight_reads++;
            if(wr && ready) begin
                for(int lane=0;lane<32;lane++) begin
                    if(result[lane*W+:W]!==sample(writes*32+lane)) $fatal(1,"Memory stream result/order");
                end
                writes++;
            end
            #1;ticks++;
            if(ticks==100 && abort) begin reset_dut();return;end
            if(ticks>20000) $fatal(1,"Memory transaction watchdog");
            // The memory must use the accepted descriptor, not these live pins.
            @(negedge clk);matrix_addr=3'(ticks);vector_addr=3'(ticks+2);dest_addr=3'(ticks+5);
        end
        if(writes!=16 || weight_reads!=MW || activation_reads!=16 || !wdone || !rdone)
            $fatal(1,"Memory frame lengths/completion W=%0d writes=%0d weights=%0d activation=%0d",W,writes,weight_reads,activation_reads);
        for(int row=0;row<512;row++)
            if(memory.mem[dst*16+row/32][(row%32)*W+:W]!==sample(row)) $fatal(1,"Destination memory mismatch");
        // A held request cannot silently launch another frame.
        repeat(5) begin
            @(negedge clk);if(ready || av || tv || wr) $fatal(1,"Held request restarted");
        end
        mode=0;repeat(3) @(negedge clk);
    endtask
    initial begin
        reset_dut();
        for(int word=0;word<DEPTH;word++) memory.mem[word]='0;
        for(int vec=0;vec<8;vec++)
            for(int row=0;row<512;row++) memory.mem[vec*16+row/32][(row%32)*W+:W]=sample(row);
        for(int mat=0;mat<8;mat++)
            for(int row=0;row<512;row++)
                memory.mem[1024+mat*MW+(row*512+row)/PER][((row*512+row)%PER)*2+:2]=2'b01;
        transaction(7,7,7,1);
        transaction(7,7,7,0);
        transaction(0,3,1,0);
        transaction(5,1,6,0);
        $display("MEMORY_PASS W=%0d frames=3 aborted=1 in_place=1 live_descriptors=1 highest_selector=7",W);$finish;
    end
endmodule
