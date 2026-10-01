`timescale 1ns/1ps
module tb_language_demo;
    logic clk=0,rst_n=0,host_en=0,host_we=0;
    logic [31:0] host_addr=0,host_wdata=0,host_rdata;
    logic host_ready,running,ready,error,overflow_out;
    logic [8:0] pc_debug;
    logic [12:0] instr_debug;
    always #5 clk=~clk;
    matmulfree dut(.*);
    integer fd,rc,op,case_id=-1,layer_id=-1,commands=0,clock_count=0,start_clock=0,runs=0,checks=0;
    logic [31:0] a,b,c;
    always @(posedge clk) clock_count=clock_count+1;
    task automatic host_write(input logic [31:0] address,data);
        @(negedge clk);host_en=1;host_we=1;host_addr=address;host_wdata=data;
        #1;if(host_ready!==1) $fatal(1,"WRITE case=%0d address=%h",case_id,address);
        @(negedge clk);host_en=0;host_we=0;
        if(address==32'h40000 && data[0]) start_clock=clock_count;
    endtask
    task automatic host_check(input logic [31:0] address,data,mask);
        integer wait_cycles;
        @(negedge clk);host_en=1;host_we=0;host_addr=address;
        #1;wait_cycles=0;
        while(host_ready!==1 && wait_cycles<4) begin
            @(negedge clk);#1;wait_cycles=wait_cycles+1;
        end
        if(host_ready!==1 || (host_rdata&mask)!==(data&mask))
            $fatal(1,"READ case=%0d layer=%0d addr=%h expected=%h actual=%h",case_id,layer_id,address,data,host_rdata);
        checks=checks+1;
        @(negedge clk);host_en=0;
    endtask
    initial begin
        integer count;
        fd=$fopen("tests/language_demo/host_vectors.txt","r");
        if(fd==0) $fatal(1,"Missing language vectors");
        while(!$feof(fd)) begin
            rc=$fscanf(fd,"%h %h %h %h",op,a,b,c);
            if(rc==4) begin
                commands=commands+1;
                case(op)
                    0: begin @(negedge clk);rst_n=0;host_en=0;host_we=0;repeat(3) @(negedge clk);rst_n=1;end
                    1: host_write(a,b);
                    2: host_check(a,b,c);
                    3: begin
                        count=0;
                        while(running && count<a) begin @(negedge clk);count=count+1;end
                        if(running) $fatal(1,"TIMEOUT case=%0d pc=%0d",case_id,pc_debug);
                        if(!ready || error || overflow_out) $fatal(1,"FLAGS case=%0d ready=%b error=%b overflow=%b",case_id,ready,error,overflow_out);
                        $display("LANGUAGE_LINEAR_PASS case=%0d layer=%0d active_cycles=%0d",case_id,layer_id,clock_count-start_clock);
                        runs=runs+1;
                        host_check(32'h40000,b,c);
                    end
                    7: begin case_id=a;layer_id=b;end
                    default: $fatal(1,"Unknown language command %0d",op);
                endcase
            end else if(!$feof(fd)) $fatal(1,"Malformed language vectors");
        end
        $fclose(fd);
        $display("LANGUAGE_DEMO_PASS commands=%0d checks=%0d runs=%0d",commands,checks,runs);
        $finish;
    end
    initial begin #100000000;$fatal(1,"LANGUAGE_GLOBAL_TIMEOUT");end
endmodule
