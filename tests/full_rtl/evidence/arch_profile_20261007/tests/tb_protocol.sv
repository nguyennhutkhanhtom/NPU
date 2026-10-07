`timescale 1ns/1ps
module tb_llm_protocol;
    logic clk=0,rst_n=0,host_en=0,host_we=0;
    logic [31:0] host_addr=0,host_wdata=0,host_rdata;
    logic host_ready,running,ready,error,overflow_out;
    logic [8:0] pc_debug;
    logic [12:0] instr_debug;
    logic [31:0] result;
    integer checks=0,token_checks=0;
    logic [6:0] fixture_position;
    logic [1:0] fixture_layer;
    logic [7:0] fixture_prompt,fixture_maximum,fixture_generated;
    logic [11:0] fixture_best;
    llm_soc dut(.*);
    always #5 clk=~clk;
    task automatic transaction(input bit write,input logic [31:0] address,data,
                               output logic [31:0] response);
        integer waits;
        @(negedge clk);host_en=1;host_we=write;host_addr=address;host_wdata=data;waits=0;
        while(!host_ready && waits<16) begin @(negedge clk);waits++;end
        if(!host_ready) $fatal(1,"LLM host timeout addr=%h",address);
        response=host_rdata;checks++;
        repeat(2) begin @(negedge clk);if(!host_ready || host_rdata!==response) $fatal(1,"LLM host held response");end
        host_en=0;host_we=0;
        @(negedge clk);if(host_ready) $fatal(1,"LLM host release");
    endtask
    task automatic check_read(input logic [31:0] address,expected);
        transaction(0,address,0,result);
        if(result!==expected) $fatal(1,"LLM host read addr=%h expected=%h actual=%h",address,expected,result);
    endtask
    // Phase injection exercises boundary indices without executing 128 layers.
    // The normal host launch below independently verifies request integration.
    task automatic reset_token_fixture;
        release dut.graph;
        @(negedge clk);rst_n=0;host_en=0;host_we=0;
        #1;
        if(dut.token_read_valid_q || dut.token_commit_valid_q || dut.token_valid_q || dut.token_q!==0)
            $fatal(1,"Token reset did not cancel pending validity");
        repeat(3) @(negedge clk);rst_n=1;
        repeat(2) @(negedge clk);
        if(dut.core_rst_n!==1) $fatal(1,"Token fixture reset release");
    endtask
    task automatic request_prefill(input integer index);
        @(negedge clk);
        seed_token_control(index-1,3,index+1,1,0,0);
        force dut.graph=dut.G_NEXT;#1;release dut.graph;
    endtask
    task automatic seed_token_control(input integer position,layer,prompt,maximum,generated,best);
        fixture_position=7'(position);fixture_layer=2'(layer);fixture_prompt=8'(prompt);
        fixture_maximum=8'(maximum);fixture_generated=8'(generated);fixture_best=12'(best);
        force dut.position_q=fixture_position;force dut.layer_q=fixture_layer;
        force dut.prompt_count_q=fixture_prompt;force dut.max_new_q=fixture_maximum;
        force dut.generated_q=fixture_generated;force dut.best_token_q=fixture_best;
        #1;
        release dut.position_q;release dut.layer_q;release dut.prompt_count_q;
        release dut.max_new_q;release dut.generated_q;release dut.best_token_q;
    endtask
    task automatic check_token_pipeline(input logic [11:0] expected,
                                        input integer position,generated);
        @(negedge clk);
        if(!dut.token_read_valid_q || dut.token_commit_valid_q || dut.token_valid_q ||
           dut.token_q!==0 || dut.graph!==dut.G_EMBED || dut.op!==dut.O_IDLE ||
           dut.position_q!==7'(position) || dut.generated_q!==8'(generated) || dut.layer_q!==0)
            $fatal(1,"Token request phase pos=%0d",position);
        @(negedge clk);
        if(dut.token_read_valid_q || !dut.token_commit_valid_q || dut.token_valid_q ||
           dut.token_q!==0 || dut.p_read || !running)
            $fatal(1,"Token prompt-read phase");
        @(negedge clk);
        if(dut.token_commit_valid_q || !dut.token_valid_q || dut.token_q!==expected ||
           dut.op!==dut.O_IDLE || dut.p_read)
            $fatal(1,"Token commit expected=%h actual=%h",expected,dut.token_q);
        @(negedge clk);
        if(dut.token_valid_q || dut.op!==dut.O_P_REQ ||
           dut.p_address_q!==15'(23040+(expected>>3)) ||
           dut.position_q!==7'(position) || dut.generated_q!==8'(generated) || dut.random_q!==1)
            $fatal(1,"Token consume/address or stalled architectural state");
        token_checks++;
    endtask
    always @(negedge clk)
        if(dut.core_rst_n && (dut.token_read_valid_q || dut.token_commit_valid_q) && dut.p_read)
            $fatal(1,"Embedding request escaped before token commit");
    initial begin
        repeat(3) @(negedge clk);rst_n=1;
        #1;if(dut.core_rst_n!==0) $fatal(1,"Reset released without clock edges");
        @(negedge clk);if(dut.core_rst_n!==0 || host_ready) $fatal(1,"Reset released on first edge");
        @(negedge clk);if(dut.core_rst_n!==1 || host_ready) $fatal(1,"Reset two-edge release contract");
        transaction(1,0,32'h12345678,result);check_read(0,32'h12345678);
        transaction(1,32'h000bfffc,32'hcafef00d,result);check_read(32'h000bfffc,32'hcafef00d);
        transaction(1,32'h000c0000,32'habcdef01,result);check_read(32'h000c0000,0);check_read(0,32'h12345678);
        transaction(1,1,32'hbadcafe0,result);check_read(1,0);check_read(0,32'h12345678);
        // Dropping enable before the execution edge cancels a pending write.
        @(negedge clk);host_en=1;host_we=1;host_addr=0;host_wdata=32'hbad00000;
        @(negedge clk);host_en=0;host_we=0;
        @(negedge clk);check_read(0,32'h12345678);
        for(integer phase=1;phase<=10;phase++) begin
            @(negedge clk);host_en=1;host_we=0;host_addr=0;
            repeat(phase) @(negedge clk);host_en=0;
            repeat(3) begin @(negedge clk);if(host_ready) $fatal(1,"Canceled host response escaped");end
            check_read(32'h000bfffc,32'hcafef00d);
        end
        force dut.graph=dut.G_DONE;
        repeat(3) @(negedge clk);
        transaction(1,0,32'hbad00001,result);check_read(0,0);check_read(32'h00400000,1);
        release dut.graph;
        repeat(3) @(negedge clk);check_read(0,32'h12345678);
        // Invalid prompt count must fail without accessing an uninitialized graph.
        transaction(1,32'h00400004,0,result);
        transaction(1,32'h0040000c,1,result);
        repeat(3) @(negedge clk);
        if(running || !error) $fatal(1,"Invalid generation configuration not rejected");
        check_read(32'h00400000,6);
        @(negedge clk);host_en=1;host_we=0;host_addr=0;
        repeat(3) @(negedge clk);rst_n=0;
        #1;if(host_ready || host_rdata!==0) $fatal(1,"Host reset cancellation");
        @(negedge clk);host_en=0;rst_n=1;
        repeat(2) @(negedge clk);check_read(0,32'h12345678);
        for(integer i=0;i<128;i++) transaction(1,32'h00100000+4*i,32'h400+i,result);
        // Real host launch: token commit must precede the embedding address.
        transaction(1,32'h00400004,2,result);transaction(1,32'h00400008,3,result);
        transaction(1,32'h0040000c,1,result);
        if(!running || error || dut.token_q!==12'h400 || dut.p_address_q!==15'(23040+128))
            $fatal(1,"Host-launched token pipeline");
        token_checks++;
        for(integer i=0;i<7;i++) begin
            reset_token_fixture();
            case(i)
                0:request_prefill(1);
                1:request_prefill(15);
                2:request_prefill(16);
                3:request_prefill(31);
                4:request_prefill(32);
                5:request_prefill(126);
                // Index 127 is an isolated read-geometry boundary; normal
                // host launch still enforces prompt_count+max_new <=128.
                6:request_prefill(127);
            endcase
            check_token_pipeline(12'(32'h400+dut.position_q+1),int'(dut.position_q)+1,0);
        end
        reset_token_fixture();
        @(negedge clk);
        seed_token_control(10,0,1,3,0,12'h5a7);
        force dut.graph=dut.G_ADVANCE;#1;release dut.graph;
        check_token_pipeline(12'h5a7,11,1);
        for(integer stop=0;stop<3;stop++) begin
            reset_token_fixture();
            @(negedge clk);
            seed_token_control(stop==2 ? 127 : 8,0,1,stop==0 ? 1 : 3,0,stop==1 ? 1 : 12'h500);
            force dut.graph=dut.G_ADVANCE;#1;release dut.graph;
            @(negedge clk);
            if(dut.graph!==dut.G_DONE || dut.generated_q!==1 || dut.token_read_valid_q ||
               dut.token_commit_valid_q || dut.token_valid_q || dut.token_q!==0 ||
               dut.position_q!==(stop==2 ? 7'd127 : 7'd8))
                $fatal(1,"Terminal token request/count case=%0d",stop);
            repeat(2) @(negedge clk);
            check_read(32'h00200000,stop==1 ? 32'd1 : 32'h500);
            token_checks++;
        end
        for(integer phase=1;phase<=3;phase++) begin
            reset_token_fixture();request_prefill(16);
            repeat(phase) @(negedge clk);
            reset_token_fixture();
            repeat(3) begin
                @(negedge clk);
                if(dut.token_read_valid_q || dut.token_commit_valid_q || dut.token_valid_q || dut.p_read)
                    $fatal(1,"Stale token pipeline after reset phase=%0d",phase);
            end
            transaction(1,32'h00100000,32'h600+phase,result);
            transaction(1,32'h00400004,1,result);transaction(1,32'h00400008,1,result);
            transaction(1,32'h0040000c,1,result);
            if(!running || error || dut.token_q!==12'(32'h600+phase))
                $fatal(1,"Token restart phase=%0d",phase);
            token_checks++;
        end
        reset_token_fixture();
        $display("LLM_PROTOCOL_PASS transactions=%0d cancellations=12 token_pipeline_cases=%0d bounds=768KiB parameter_read_pipeline=5 reset_release_edges=2",checks,token_checks);$finish;
    end
    initial begin #1000000;$fatal(1,"LLM_PROTOCOL_TIMEOUT");end
endmodule
