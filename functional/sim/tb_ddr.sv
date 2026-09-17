`timescale 1ns/1ps
module tb_ddr;
    parameter W=8;
    localparam DW=W*32;
    logic clk=0,rst=1,ui_reset=0,calib=1,rd_req=0,wr_req=0;
    logic [3:0] rd_len=0,wr_len=0;
    logic [5:0] rd_addr=0,wr_addr=0;
    logic [DW-1:0] source='0,read_data='0;
    logic rd_valid=0,app_ready=0,data_ready=0;
    wire [8:0] app_addr;
    wire [2:0] cmd;
    wire en,wdf_valid,wdf_end,request_word,result_valid,rf,wf,finish,error;
    wire [DW-1:0] wdf_data,result;
    always #5 clk=~clk;
    mem_burst #(.MEM_DATA_BITS(DW),.ADDR_BITS(6),.LEN_BITS(4),.ADDR_SHIFT(3)) dut(
        .rst(rst),.mem_clk(clk),.rd_burst_req(rd_req),.wr_burst_req(wr_req),
        .rd_burst_len(rd_len),.wr_burst_len(wr_len),.rd_burst_addr(rd_addr),.wr_burst_addr(wr_addr),
        .rd_burst_data_valid(result_valid),.wr_burst_data_req(request_word),.rd_burst_data(result),
        .wr_burst_data(source),.rd_burst_finish(rf),.wr_burst_finish(wf),.burst_finish(finish),
        .burst_error(error),.app_addr(app_addr),.app_cmd(cmd),.app_en(en),.app_wdf_data(wdf_data),
        .app_wdf_end(wdf_end),.app_wdf_wren(wdf_valid),.app_rd_data(read_data),
        .app_rd_data_end(1'b1),.app_rd_data_valid(rd_valid),.app_rdy(app_ready),.app_wdf_rdy(data_ready),
        .ui_clk_sync_rst(ui_reset),.init_calib_complete(calib));
    bit monitor=0,writing=0,command_hold=0,data_hold=0,force_stall=0;
    int commands=0,data_words=0,requests=0,responses=0,base=0,length=0,ticks=0;
    logic [8:0] held_addr;
    logic [2:0] held_cmd;
    logic [DW-1:0] held_data;
    function automatic [DW-1:0] pattern(input int index);
        for(int lane=0;lane<32;lane++) pattern[lane*W+:W]=W'(index*17+lane);
    endfunction
    always @(negedge clk) begin
        ticks++;
        app_ready=monitor && !force_stall && ticks%3!=0;
        data_ready=monitor && !force_stall && ticks%5!=0;
        rd_valid=monitor && !writing && !force_stall && responses<commands && ticks%4!=0;
        read_data=pattern(responses);
    end
    always @(posedge clk) if(monitor && !rst && !ui_reset && calib) begin
        if(command_hold && (!en || app_addr!==held_addr || cmd!==held_cmd)) $fatal(1,"DDR command changed under stall");
        if(data_hold && (!wdf_valid || !wdf_end || wdf_data!==held_data)) $fatal(1,"DDR WDF changed under stall");
        if(request_word) begin source<=pattern(requests);requests++;end
        if(en && app_ready) begin
            if(commands>=length || app_addr!==9'((base+commands)*8) || cmd!==(writing ? 3'd0 : 3'd1))
                $fatal(1,"DDR command address/count cmd=%0d got=%0d",commands,app_addr);
            commands++;
        end
        if(wdf_valid && data_ready) begin
            if(!wdf_end || wdf_data!==pattern(data_words) || data_words>=length) $fatal(1,"DDR data/END/count");
            data_words++;
        end
        if(result_valid) begin
            if(result!==pattern(responses) || responses>=length) $fatal(1,"DDR read response");
            responses++;
        end
        command_hold=en&&!app_ready;held_addr=app_addr;held_cmd=cmd;
        data_hold=wdf_valid&&!data_ready;held_data=wdf_data;
    end
    task automatic transaction(input bit wr,input int count,input int address,input bit invalid_range);
        @(negedge clk);
        monitor=1;writing=wr;base=address;length=count;
        commands=0;data_words=0;requests=0;responses=0;command_hold=0;data_hold=0;
        rd_len=4'(count);wr_len=4'(count);rd_addr=6'(address);wr_addr=6'(address);
        rd_req=!wr;wr_req=wr;
        @(negedge clk);rd_req=0;wr_req=0;
        rd_len=1;wr_len=2;rd_addr=3;wr_addr=4;
        wait(finish);#1;
        if(error!==invalid_range || wf!==wr || rf===wr) $fatal(1,"DDR completion/error type");
        if(invalid_range || count==0) begin
            if(commands || data_words || requests || responses) $fatal(1,"DDR rejected/noop issued traffic");
        end else if(commands!=count || (wr && (data_words!=count || requests!=count)) || (!wr && responses!=count))
            $fatal(1,"DDR wrong accepted beat counts");
        @(negedge clk);monitor=0;
        @(negedge clk);if(finish || en || wdf_valid) $fatal(1,"DDR idle/done pulse");
    endtask
    initial begin
        repeat(3) @(negedge clk);rst=0;
        transaction(0,0,63,0);transaction(1,0,63,0);
        transaction(0,1,63,0);transaction(1,1,63,0);
        transaction(0,2,8,0);transaction(1,2,8,0);
        transaction(0,15,2,0);transaction(1,15,2,0);
        transaction(0,2,63,1);transaction(1,2,63,1);
        // Reset and calibration loss while a WDF beat is waiting.
        for(int test=0;test<2;test++) begin
            @(negedge clk);monitor=1;writing=1;force_stall=1;commands=0;data_words=0;requests=0;
            responses=0;command_hold=0;data_hold=0;base=0;length=2;wr_len=2;wr_addr=0;wr_req=1;
            @(negedge clk);wr_req=0;
            wait(wdf_valid);
            @(negedge clk);if(test==0) ui_reset=1;else calib=0;
            #1;if(en || wdf_valid || request_word || finish) $fatal(1,"DDR reset/calibration output gating");
            command_hold=0;data_hold=0;
            repeat(2) @(negedge clk);
            ui_reset=0;calib=1;monitor=0;force_stall=0;
            repeat(3) @(negedge clk);
            if(en || wdf_valid || finish) $fatal(1,"DDR aborted request resumed");
        end
        transaction(1,2,1,0);
        $display("DDR_PASS W=%0d lengths=0,1,2,15 boundary=1 reset=1 backpressure=1",W);$finish;
    end
    initial begin #50000;$fatal(1,"DDR watchdog");end
endmodule
