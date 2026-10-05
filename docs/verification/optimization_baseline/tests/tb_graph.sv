`timescale 1ns/1ps
// Synthetic host-loaded graph regression. This is not a trained model demo.
// Zero projection weights leave the embedding residual intact; positive token
// 3 then has the unique maximum tied-head score at every decode position.
module tb_llm_graph;
    logic clk=0,rst_n=0,host_en=0,host_we=0;
    logic [31:0] host_addr=0,host_wdata=0,host_rdata;
    logic host_ready,running,ready,error,overflow_out;
    logic [8:0] pc_debug;
    logic [12:0] instr_debug;
    llm_soc dut(.*);
    always #5 clk=~clk;
    logic [255:0] image[0:24575];
    logic [31:0] response;
    integer pointer,columns,rows,commands=0,clocks=0;
    integer visits[0:23];
    logic [4:0] previous_graph=0;
    always @(negedge clk) begin
        if(rst_n) begin
            if(!$onehot(dut.op)) $fatal(1,"Operator control lost one-hot invariant");
            if(dut.core_rst_n && dut.round16_group_q!=={8{dut.op[dut.NR_ROUND_IDX] || dut.op[dut.B_ROUND_IDX]}})
                $fatal(1,"Round command lost its predecessor/consumer alignment");
            if((dut.token_read_valid_q || dut.token_commit_valid_q) && dut.p_read)
                $fatal(1,"Embedding request before token commit");
            if(dut.graph!=previous_graph) visits[dut.graph]++;
            previous_graph=dut.graph;
            if(dut.k_read && dut.k_address_q[9:3]>dut.position_q)
                $fatal(1,"Noncausal cache read address=%0d position=%0d",dut.k_address_q,dut.position_q);
        end else previous_graph=0;
    end
    task automatic transaction(input bit write,input logic [31:0] address,data);
        integer waits;
        @(negedge clk);host_en=1;host_we=write;host_addr=address;host_wdata=data;waits=0;
        while(!host_ready && waits<16) begin @(negedge clk);waits++;end
        if(!host_ready) $fatal(1,"Graph host timeout address=%h",address);
        response=host_rdata;commands++;
        @(negedge clk);host_en=0;host_we=0;
        @(negedge clk);if(host_ready) $fatal(1,"Graph host response did not retire");
    endtask
    initial begin
        for(integer phase=0;phase<24;phase++) visits[phase]=0;
        for(integer row=0;row<24576;row++) image[row]=0;
        for(integer row=0;row<4;row++) begin
            image[3*4+row]={32{8'd1}};
            image[5*4+row]={32{8'hff}};
        end
        for(integer row=23040;row<23552;row++) image[row]={8{32'h00100000}};
        pointer=16384;
        for(integer layer=0;layer<4;layer++)
            for(integer matrix_id=0;matrix_id<7;matrix_id++) begin
                columns=matrix_id==6 ? 384 : 128;
                rows=matrix_id==4 || matrix_id==5 ? 384 : 128;
                image[23552+layer*7+matrix_id]=0;
                image[23552+layer*7+matrix_id][14:0]=15'(pointer);
                image[23552+layer*7+matrix_id][24:15]=10'(columns);
                image[23552+layer*7+matrix_id][34:25]=10'(rows);
                image[23552+layer*7+matrix_id][58:35]=24'h100000;
                pointer+=rows*columns/128;
            end
        if(pointer!=23040) $fatal(1,"Synthetic image layout");
        for(integer row=23580;row<23652;row++) image[row]={16{16'd4096}};
        for(integer row=23652;row<23908;row++) image[row]={8{32'h00007fff}};
        repeat(3) @(negedge clk);rst_n=1;
        for(integer row=0;row<24576;row++)
            for(integer lane=0;lane<8;lane++) transaction(1,32'(row*32+lane*4),image[row][lane*32+:32]);
        transaction(1,32'h00100000,5);transaction(1,32'h00100004,3);
        transaction(1,32'h00400004,2);transaction(1,32'h00400008,3);
        transaction(1,32'h00400010,0);transaction(1,32'h00400018,0);
        transaction(1,32'h0040000c,1);
        if(!running) $fatal(1,"Synthetic graph did not start");
        // Scalar distribution adds 24576 clocks and four token fetches add 8.
        // Keep the existing bound and all numeric/token/causal assertions.
        while(running && clocks<5000000) begin
            @(negedge clk);clocks++;
            if(clocks%500000==0) $display("LLM_GRAPH_PROGRESS clocks=%0d position=%0d generated=%0d",clocks,dut.position_q,dut.generated_q);
        end
        if(running || error || overflow_out) $fatal(1,"Synthetic graph failed clocks=%0d error=%b overflow=%b",clocks,error,overflow_out);
        transaction(0,32'h00400000,0);
        if(response!==32'h32) $fatal(1,"Synthetic graph status=%h",response);
        for(integer token=0;token<3;token++) begin
            transaction(0,32'h00200000+token*4,0);
            if(response!==32'd3) $fatal(1,"Synthetic token index=%0d actual=%0d",token,response);
        end
        for(integer phase=1;phase<=23;phase++) begin
            if(phase==1 && visits[phase]!=4 || phase>=2 && phase<=18 && visits[phase]!=16 ||
               phase==19 && visits[phase]!=16 || phase>=20 && phase<=22 && visits[phase]!=3 ||
               phase==23 && visits[phase]!=1)
                $fatal(1,"Synthetic graph phase=%0d visits=%0d",phase,visits[phase]);
        end
        $display("LLM_GRAPH_PASS prompt=2 tokens=3 layers=16 causal=checked clocks=%0d host_commands=%0d fixtures=synthetic",clocks,commands);
        $finish;
    end
    // 196619 host commands, <=19edges each, plus <=5M compute clocks <90ms.
    initial begin #100000000;$fatal(1,"LLM_GRAPH_TIMEOUT");end
endmodule
