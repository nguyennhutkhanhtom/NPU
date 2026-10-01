`timescale 1ns/1ps
module tb_model_demo;
    logic clk=0,rst_n=0,host_en=0,host_we=0;
    logic [31:0] host_addr=0,host_wdata=0,host_rdata;
    logic host_ready,running,ready,error,overflow_out;
    logic [8:0] pc_debug;
    logic [12:0] instr_debug;
    always #5 clk=~clk;
    matmulfree dut(.*);
    integer fd,rc,op,case_id=-1,layer_id=-1,commands=0,clock_count=0,start_clock=0,run_count=0;
    integer host_checks=0,sample_checks=0;
    logic [31:0] a,b,c;
    logic signed [31:0] logits[0:9];
    always @(posedge clk) clock_count=clock_count+1;
    task automatic host_write(input logic [31:0] address,data);
        @(negedge clk);host_en=1;host_we=1;host_addr=address;host_wdata=data;
        #1;if(host_ready!==1) $fatal(1,"WRITE rejected case=%0d address=%h",case_id,address);
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
        if(layer_id>=3 && address>=32'h10a00 && address<32'h10a28)
            logits[(address-32'h10a00)/4]=host_rdata;
        host_checks=host_checks+1;
        @(negedge clk);host_en=0;
    endtask
    initial begin
        integer count,best;
        fd=$fopen("tests/model_demo/host_vectors.txt","r");
        if(fd==0) $fatal(1,"Missing demo host vectors");
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
                        if(running) $fatal(1,"TIMEOUT case=%0d layer=%0d pc=%0d",case_id,layer_id,pc_debug);
                        if(!ready || error || overflow_out) $fatal(1,"MODEL flags case=%0d layer=%0d ready=%b error=%b overflow=%b",case_id,layer_id,ready,error,overflow_out);
                        $display("MODEL_RUN_DONE sample=%0d layer=%0d active_cycles=%0d",case_id,layer_id,clock_count-start_clock);
                        run_count=run_count+1;
                        host_check(32'h40000,b,c);
                    end
                    7: case_id=a;
                    8: layer_id=a;
                    9: begin
                        best=0;
                        for(integer index=1;index<10;index=index+1) if(logits[index]>logits[best]) best=index;
                        if(best!=c) $fatal(1,"ARGMAX sample=%0d expected=%0d actual=%0d",case_id,c,best);
                        $display("MODEL_SAMPLE_PASS sample=%0d label=%0d cpu_prediction=%0d rtl_prediction=%0d",case_id,a,b,best);
                        sample_checks=sample_checks+1;
                    end
                    default: $fatal(1,"Unknown model command %0d",op);
                endcase
            end else if(!$feof(fd)) $fatal(1,"Malformed demo vectors");
        end
        $fclose(fd);
        $display("MODEL_DEMO_PASS commands=%0d host_checks=%0d samples_and_repeats=%0d runs=%0d",commands,host_checks,sample_checks,run_count);
        $finish;
    end
    initial begin #100000000;$fatal(1,"MODEL_GLOBAL_TIMEOUT");end
endmodule
