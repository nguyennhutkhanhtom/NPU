`timescale 1ns/1ps
module tb_llm_ram;
    logic clk=0,rd_en=0,wr_en=0;
    logic [11:0] rd_addr=0,wr_addr=0;
    logic [31:0] wr_data=0,rd_data;
    integer checks=0;
    integer addresses[0:8]='{0,1,1022,1023,1024,2047,2048,3070,3071};
    banked_word_ram #(.ROWS(3072),.ADDR_W(12)) dut(.*);
    logic rst_n=0,b_rd_en=0,b_rd_valid;
    logic [11:0] b_rd_addr=0,b_wr_addr=0;
    logic [1:0] b_wr_mask=0;
    logic [63:0] b_wr_data=0,b_rd_data;
    llm_bank_ram #(.LANES(2),.WIDTH(32),.ROWS(3072),.ADDR_W(12)) adapter(
        .clk(clk),.rst_n(rst_n),.rd_en(b_rd_en),.rd_addr(b_rd_addr),.rd_data(b_rd_data),.rd_valid(b_rd_valid),
        .wr_addr(b_wr_addr),.wr_mask(b_wr_mask),.wr_data(b_wr_data));
    always #5 clk=~clk;
    task automatic read_check(input integer address,input logic [31:0] expected);
        @(negedge clk);rd_en=1;rd_addr=12'(address);
        @(negedge clk);rd_en=0;
        #1;if(rd_data!==expected) $fatal(1,"Tiled RAM address=%0d expected=%h actual=%h",address,expected,rd_data);
        checks++;
    endtask
    task automatic adapter_write(input integer address,input logic [1:0] mask,input logic [63:0] data);
        @(negedge clk);b_wr_addr=12'(address);b_wr_mask=mask;b_wr_data=data;
        @(negedge clk);b_wr_mask=0;b_wr_addr=0;b_wr_data='1;
        @(negedge clk);
    endtask
    task automatic adapter_read(input integer address,input logic [63:0] expected);
        @(negedge clk);b_rd_en=1;b_rd_addr=12'(address);
        @(negedge clk);b_rd_en=0;b_rd_addr=0;
        #1;if(b_rd_valid) $fatal(1,"Adapter responded before second edge");
        @(negedge clk);
        #1;if(!b_rd_valid || b_rd_data!==expected) $fatal(1,"Adapter read addr=%0d expected=%h actual=%h valid=%b",address,expected,b_rd_data,b_rd_valid);
        checks++;
        @(negedge clk);#1;if(b_rd_valid) $fatal(1,"Adapter response did not retire");
    endtask
    initial begin
        for(integer i=0;i<9;i++) begin
            @(negedge clk);wr_en=1;wr_addr=12'(addresses[i]);wr_data=32'h12340000+addresses[i];
            @(negedge clk);wr_en=0;
        end
        for(integer i=8;i>=0;i--) read_check(addresses[i],32'h12340000+addresses[i]);
        @(negedge clk);rd_en=1;wr_en=1;rd_addr=1024;wr_addr=1024;wr_data=32'habcdef12;
        @(negedge clk);rd_en=0;wr_en=0;
        #1;if(rd_data!==32'h12340400) $fatal(1,"Tiled RAM collision must return old data");
        read_check(1024,32'habcdef12);
        read_check(2048,32'h12340800);
        repeat(3) begin @(negedge clk);#1;if(rd_data!==32'h12340800) $fatal(1,"Tiled RAM idle data changed");end
        rst_n=1;
        adapter_write(1024,2'b11,64'h12345678_abcdef01);
        adapter_write(2048,2'b11,64'h22222222_11111111);
        adapter_read(1024,64'h12345678_abcdef01);
        @(negedge clk);b_rd_en=1;b_rd_addr=1024;b_wr_addr=1024;b_wr_mask=1;b_wr_data=64'hdeadbeef_76543210;
        @(negedge clk);b_rd_en=0;b_wr_mask=0;b_rd_addr=0;b_wr_addr=0;b_wr_data=0;
        @(negedge clk);
        #1;if(!b_rd_valid || b_rd_data!==64'h12345678_abcdef01) $fatal(1,"Pipelined collision was not old data");
        checks++;
        @(negedge clk);
        adapter_read(1024,64'h12345678_76543210);
        // Consecutive requests retain their own address and valid tags.
        @(negedge clk);b_rd_en=1;b_rd_addr=1024;
        @(negedge clk);b_rd_addr=2048;
        @(negedge clk);b_rd_en=0;
        #1;if(!b_rd_valid || b_rd_data!==64'h12345678_76543210) $fatal(1,"First back-to-back response mismatch");
        checks++;
        @(negedge clk);
        #1;if(!b_rd_valid || b_rd_data!==64'h22222222_11111111) $fatal(1,"Second back-to-back response mismatch");
        checks++;
        @(negedge clk);#1;if(b_rd_valid) $fatal(1,"Back-to-back response did not retire");
        // Reset after acceptance cancels pending read and write without clearing storage.
        @(negedge clk);b_rd_en=1;b_rd_addr=1024;b_wr_mask=3;b_wr_addr=1024;b_wr_data=0;
        @(negedge clk);rst_n=0;b_rd_en=0;b_wr_mask=0;
        #1;if(b_rd_valid) $fatal(1,"Reset did not cancel valid");
        @(negedge clk);rst_n=1;
        adapter_read(1024,64'h12345678_76543210);
        $display("LLM_RAM_PASS checks=%0d tile_boundaries=4 collision=old_data adapter_latency=2 mask=checked back_to_back=2 reset_cancellation=checked",checks);$finish;
    end
endmodule
