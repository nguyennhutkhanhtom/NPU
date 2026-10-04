`timescale 1ns/1ps
// Actual Intel simulation library versus the replaceable ASIC SRAM model.
// Independent expected words check both implementations; no internal seeding.
module memory_ip_case #(parameter int WIDTH=32, ROWS=3072, ADDR_W=$clog2(ROWS))
    (input logic clk, output logic finished=0, output integer checks=0);
    localparam int LATENCY=ROWS<=4096 ? 3 : 4;
    logic rst_n=0,rd_en=0,wr_en=0;
    logic [ADDR_W-1:0] rd_addr=0,wr_addr=0;
    logic [WIDTH-1:0] wr_data=0,model_data,ip_data;
    logic model_valid,ip_valid,model_commit,ip_commit;
    pipelined_word_ram #(.WIDTH(WIDTH),.ROWS(ROWS),.ADDR_W(ADDR_W),.USE_QUARTUS_MEMORY(0)) model(
        .clk(clk),.rst_n(rst_n),.rd_en(rd_en),.wr_en(wr_en),.rd_addr(rd_addr),.wr_addr(wr_addr),
        .wr_data(wr_data),.rd_data(model_data),.rd_valid(model_valid),.wr_valid(model_commit));
    pipelined_word_ram #(.WIDTH(WIDTH),.ROWS(ROWS),.ADDR_W(ADDR_W),.USE_QUARTUS_MEMORY(1)) ip(
        .clk(clk),.rst_n(rst_n),.rd_en(rd_en),.wr_en(wr_en),.rd_addr(rd_addr),.wr_addr(wr_addr),
        .wr_data(wr_data),.rd_data(ip_data),.rd_valid(ip_valid),.wr_valid(ip_commit));
    always @(negedge clk) if(rst_n) begin
        if(ip_valid!==model_valid || ip_commit!==model_commit)
            $fatal(1,"IP validity mismatch rows=%0d",ROWS);
        if(ip_valid && ip_data!==model_data)
            $fatal(1,"IP/model data rows=%0d ip=%h model=%h",ROWS,ip_data,model_data);
    end
    task automatic write_word(input integer address,input logic [WIDTH-1:0] value);
        @(negedge clk);wr_en=1;wr_addr=ADDR_W'(address);wr_data=value;
        @(negedge clk);wr_en=0;
        @(negedge clk);if(!ip_commit) $fatal(1,"Write commit latency rows=%0d",ROWS);
        @(negedge clk);if(ip_commit) $fatal(1,"Repeated commit");checks++;
    endtask
    task automatic read_word(input integer address,input logic [WIDTH-1:0] value);
        integer edges;
        @(negedge clk);rd_en=1;rd_addr=ADDR_W'(address);
        @(negedge clk);rd_en=0;edges=1;
        while(!ip_valid && edges<8) begin @(negedge clk);edges++;end
        if(edges!=LATENCY || !ip_valid || ip_data!==value)
            $fatal(1,"IP read rows=%0d address=%0d edges=%0d expected=%h actual=%h",ROWS,address,edges,value,ip_data);
        @(negedge clk);if(ip_valid) $fatal(1,"Repeated read valid");checks++;
    endtask
    initial begin
        repeat(3) @(negedge clk);rst_n=1;
        for(integer i=0;i<12;i++) begin
            write_word((i*1023)%ROWS,WIDTH'(32'h13570000+i));
            read_word((i*1023)%ROWS,WIDTH'(32'h13570000+i));
        end
        write_word(0,WIDTH'(32'h12345678));
        write_word(ROWS-1,WIDTH'(32'hdeadbeef));
        // Consecutive reads must retain order and one-response-per-request.
        @(negedge clk);rd_en=1;rd_addr=0;
        @(negedge clk);rd_addr=ADDR_W'(ROWS-1);
        @(negedge clk);rd_en=0;
        repeat(LATENCY-2) @(negedge clk);
        if(!ip_valid || ip_data!==WIDTH'(32'h12345678)) $fatal(1,"Back-to-back first");
        @(negedge clk);if(!ip_valid || ip_data!==WIDTH'(32'hdeadbeef)) $fatal(1,"Back-to-back second");
        @(negedge clk);if(ip_valid) $fatal(1,"Extra back-to-back response");checks+=3;
        // Same accepted-cycle read and write must return the OLD word.
        @(negedge clk);rd_en=1;wr_en=1;rd_addr=0;wr_addr=0;wr_data=WIDTH'(32'h76543210);
        @(negedge clk);rd_en=0;wr_en=0;
        repeat(LATENCY-1) @(negedge clk);
        if(!ip_valid || ip_data!==WIDTH'(32'h12345678)) $fatal(1,"IP old-data collision");checks++;
        @(negedge clk);read_word(0,WIDTH'(32'h76543210));
        // Reset before leaf write commit cancels the queued write, retaining RAM.
        @(negedge clk);wr_en=1;wr_addr=0;wr_data=0;
        @(negedge clk);wr_en=0;rst_n=0;
        repeat(2) @(negedge clk);if(ip_valid || ip_commit) $fatal(1,"Reset validity");rst_n=1;
        read_word(0,WIDTH'(32'h76543210));checks++;
        for(integer phase=0;phase<LATENCY;phase++) begin
            @(negedge clk);rd_en=1;rd_addr=0;
            repeat(phase) @(negedge clk);
            rst_n=0;rd_en=0;
            repeat(2) @(negedge clk);rst_n=1;
            repeat(LATENCY+1) begin @(negedge clk);if(ip_valid) $fatal(1,"Stale reset response");end
            read_word(0,WIDTH'(32'h76543210));checks++;
        end
        finished=1;
    end
endmodule
module tb_quartus_memory;
    logic clk=0;
    wire [3:0] finished;
    integer c0,c1,c2,c3;
    always #5 clk=~clk;
    memory_ip_case #(.WIDTH(24),.ROWS(96)) vector_bank(clk,finished[0],c0);
    memory_ip_case #(.WIDTH(24),.ROWS(4096)) cache_bank(clk,finished[1],c1);
    memory_ip_case #(.WIDTH(32),.ROWS(3072)) small_parameter(clk,finished[2],c2);
    memory_ip_case #(.WIDTH(32),.ROWS(24576)) full_parameter(clk,finished[3],c3);
    initial begin
        wait(&finished);@(negedge clk);
        $display("QUARTUS_MEMORY_PASS banks=4 checks=%0d collision=OLD_DATA read=3/4 write=2 reset=cancels_queue storage=retained",c0+c1+c2+c3);
        $finish;
    end
    initial begin #100000; $fatal(1,"Memory IP test timeout");end
endmodule
