`timescale 1ns/1ps
// Portable SRAM backend checked against independent expected words.
// No vendor model or internal seeding; retain latency/collision/reset checks.
module memory_ip_case #(parameter int WIDTH=32, ROWS=3072, ADDR_W=$clog2(ROWS))
    (input logic clk, output logic finished=0, output integer checks=0);
    localparam int LATENCY=ROWS<=4096 ? 3 : 4;
    localparam int TILES=(ROWS+1023)/1024;
    localparam int BOUNDARIES=2*TILES;
    integer boundary_address [0:BOUNDARIES-1];
    logic [WIDTH-1:0] boundary_value [0:BOUNDARIES-1];
    logic [WIDTH-1:0] held_data;
    logic rst_n=0,rd_en=0,wr_en=0;
    logic [ADDR_W-1:0] rd_addr=0,wr_addr=0;
    logic [WIDTH-1:0] wr_data=0,ip_data;
    logic ip_valid,ip_commit;
    pipelined_word_ram #(.WIDTH(WIDTH),.ROWS(ROWS),.ADDR_W(ADDR_W),.USE_QUARTUS_MEMORY(0)) ip(
        .clk(clk),.rst_n(rst_n),.rd_en(rd_en),.wr_en(wr_en),.rd_addr(rd_addr),.wr_addr(wr_addr),
        .wr_data(wr_data),.rd_data(ip_data),.rd_valid(ip_valid),.wr_valid(ip_commit));
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
        // Exercise every tile start/end, including all response-group crossings.
        // Values distinguish adjacent transactions and stale held leaf outputs.
        for(integer tile=0;tile<TILES;tile++) begin
            boundary_address[2*tile]=tile*1024;
            boundary_address[2*tile+1]=(tile+1)*1024<ROWS ? (tile+1)*1024-1 : ROWS-1;
            boundary_value[2*tile]=WIDTH'(32'ha5300000+2*tile);
            boundary_value[2*tile+1]=WIDTH'(32'ha5300001+2*tile);
            write_word(boundary_address[2*tile],boundary_value[2*tile]);
            write_word(boundary_address[2*tile+1],boundary_value[2*tile+1]);
        end
        // Sustained simultaneous read/write traffic checks old-data on every
        // address, one response per cycle, and exact leaf commit timing.
        for(integer cycle=0;cycle<BOUNDARIES+LATENCY+1;cycle++) begin
            @(negedge clk);
            if(cycle>=LATENCY && cycle<BOUNDARIES+LATENCY) begin
                if(!ip_valid || ip_data!==boundary_value[cycle-LATENCY])
                    $fatal(1,"Boundary stream rows=%0d cycle=%0d actual=%h",ROWS,cycle,ip_data);
                checks++;
            end else if(ip_valid) $fatal(1,"Unexpected boundary stream response rows=%0d",ROWS);
            if(ip_commit!==(cycle>=2 && cycle<BOUNDARIES+2))
                $fatal(1,"Boundary stream commit rows=%0d cycle=%0d",ROWS,cycle);
            rd_en=cycle<BOUNDARIES;wr_en=cycle<BOUNDARIES;
            if(cycle<BOUNDARIES) begin
                rd_addr=ADDR_W'(boundary_address[cycle]);wr_addr=ADDR_W'(boundary_address[cycle]);
                wr_data=boundary_value[cycle]^WIDTH'(32'h0055aaff);
            end
        end
        for(integer index=0;index<BOUNDARIES;index++)
            read_word(boundary_address[index],boundary_value[index]^WIDTH'(32'h0055aaff));
        // Different tiles may read and write on the same accepting edge.
        @(negedge clk);rd_en=1;wr_en=1;rd_addr=0;wr_addr=ADDR_W'(ROWS-1);
        wr_data=WIDTH'(32'h2468ace0);
        @(negedge clk);rd_en=0;wr_en=0;
        repeat(LATENCY-1) @(negedge clk);
        if(!ip_valid || ip_data!==(boundary_value[0]^WIDTH'(32'h0055aaff)))
            $fatal(1,"Independent read/write rows=%0d",ROWS);
        checks++;
        @(negedge clk);read_word(ROWS-1,WIDTH'(32'h2468ace0));
        held_data=ip_data;
        repeat(LATENCY+2) begin
            @(negedge clk);rd_addr=~rd_addr;
            if(ip_valid || ip_commit || ip_data!==held_data) $fatal(1,"Disabled output hold rows=%0d",ROWS);
            checks++;
        end
        finished=1;
    end
endmodule
module tb_llm_memory;
    logic clk=0;
    wire [4:0] finished;
    integer c0,c1,c2,c3,c4;
    always #5 clk=~clk;
    memory_ip_case #(.WIDTH(24),.ROWS(96)) vector_bank(clk,finished[0],c0);
    memory_ip_case #(.WIDTH(24),.ROWS(4096)) cache_bank(clk,finished[1],c1);
    memory_ip_case #(.WIDTH(32),.ROWS(3072)) small_parameter(clk,finished[2],c2);
    memory_ip_case #(.WIDTH(32),.ROWS(24576)) full_parameter(clk,finished[3],c3);
    memory_ip_case #(.WIDTH(32),.ROWS(5123)) partial_parameter(clk,finished[4],c4);
    initial begin
        wait(&finished);@(negedge clk);
        $display("LLM_MEMORY_PASS banks=5 checks=%0d collision=OLD_DATA read=3/4 write=2 reset=cancels_queue storage=retained tile_boundaries=all sustained_read_write=checked partial_tile_group=checked",c0+c1+c2+c3+c4);
        $finish;
    end
    initial begin #100000; $fatal(1,"Memory IP test timeout");end
endmodule
