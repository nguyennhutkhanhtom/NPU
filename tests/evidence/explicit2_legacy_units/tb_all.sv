// Testbenches for the current main RTL. Select a block with tests/run.ps1.

// tb_host.sv
`timescale 1ns/1ps
module tb_host;
    logic clk=0,rst_n=0,host_en=0,host_we=0;
    logic [31:0] host_addr=0,host_wdata=0,host_rdata;
    logic host_ready,running,ready,error,overflow_out;
    logic [8:0] pc_debug;
    logic [12:0] instr_debug;
    always #5 clk=~clk;
    matmulfree dut(.*);
    // Arbitration checks belong to verification, independent of RTL build flags.
    always @(posedge clk) begin
        if(rst_n) begin
            if(dut.u_imem.fetch_en && dut.u_imem.host_en)
                $fatal(1,"Instruction clients overlap");
            if(dut.u_ws.host_en && (dut.u_ws.rd_en || dut.u_ws.wr_en ||
               (dut.u_ws.u_sram.read_pending_q && !dut.u_ws.u_sram.read_host_q)))
                $fatal(1,"Workspace memory clients overlap");
            if(dut.u_param.host_en && (dut.u_param.rd_en || dut.u_param.wr_en ||
               (dut.u_param.u_sram.read_pending_q && !dut.u_param.u_sram.read_host_q)))
                $fatal(1,"Parameter memory clients overlap");
        end
    end
    integer fd,rc,op,case_id=0,count=0,cases_run=0;
    integer protocol_reads=0,protocol_cancels=0,protocol_blocked=0,quant_selector_checks=0;
    logic [31:0] a,b,c;
    task automatic host_write(input logic [31:0] addr,data,input bit accepted);
        @(negedge clk);host_en=1;host_we=1;host_addr=addr;host_wdata=data;
        #1;if(host_ready!==accepted) $fatal(1,"host ready case=%0d addr=%h expected=%b got=%b",case_id,addr,accepted,host_ready);
        @(negedge clk);host_en=0;host_we=0;
    endtask
    task automatic host_check(input logic [31:0] addr,data,mask);
        integer wait_cycles;
        @(negedge clk);host_en=1;host_we=0;host_addr=addr;
        #1;
        // SRAM and instruction reads are synchronous. Hold the request until the matching
        // response is ready, with a bound that catches a lost response.
        wait_cycles=0;
        while(host_ready!==1 && wait_cycles<4) begin
            @(negedge clk);
            #1;
            wait_cycles=wait_cycles+1;
        end
        if(host_ready!==1 || (host_rdata&mask)!==(data&mask))
            $fatal(1,"READ case=%0d addr=%h expected=%h actual=%h mask=%h",case_id,addr,data,host_rdata,mask);
        @(negedge clk);host_en=0;
    endtask

    task automatic protocol_wait(input logic [31:0] data,input integer latency);
        #1;if(host_ready!==0) $fatal(1,"New host read accepted a stale response addr=%h",host_addr);
        for(integer edge_count=1;edge_count<=latency;edge_count++) begin
            @(negedge clk);#1;
            if(host_ready!==(edge_count==latency))
                $fatal(1,"Host read latency addr=%h edge=%0d expected_edges=%0d ready=%b",host_addr,edge_count,latency,host_ready);
        end
        if(host_rdata!==data) $fatal(1,"Host protocol data addr=%h expected=%h actual=%h",host_addr,data,host_rdata);
        protocol_reads++;
    endtask

    task automatic protocol_release;
        host_en=0;host_we=0;
        #1;if(host_ready!==0) $fatal(1,"Host ready after request release");
        @(negedge clk);#1;
        if(host_ready!==0 || host_rdata!==0) $fatal(1,"Host response remained valid after release");
    endtask

    task automatic protocol_read(input logic [31:0] addr,data,input integer latency);
        @(negedge clk);host_en=1;host_we=0;host_addr=addr;
        protocol_wait(data,latency);
        repeat(2) begin
            @(negedge clk);#1;
            if(host_ready!==1 || host_rdata!==data) $fatal(1,"Held host response changed addr=%h",addr);
        end
        protocol_release();
    endtask

    task automatic check_host_protocol;
        logic [31:0] blocked_addresses[0:3];
        integer clocks;
        blocked_addresses='{32'h00000000,32'h00010000,32'h00020000,32'h00030000};
        @(negedge clk);rst_n=0;host_en=0;host_we=0;
        repeat(2) @(negedge clk);rst_n=1;
        host_write(32'h00000000,32'h13579bdf,1);
        host_write(32'h00000004,32'h2468ace0,1);
        host_write(32'h00010000,32'h11223344,1);
        host_write(32'h00010004,32'h55667788,1);
        host_write(32'h00020000,32'h01a5f00d,1);
        host_write(32'h00020100,32'h10203040,1);
        host_write(32'h00020104,32'h50607080,1);
        host_write(32'h00020108,32'h90a0b0c0,1);
        host_write(32'h00040010,32'h00000099,1);
        host_write(32'h00040014,32'h13572468,1);
        protocol_read(32'h00000000,32'h13579bdf,4);
        protocol_read(32'h00000004,32'h2468ace0,4);
        protocol_read(32'h00010000,32'h11223344,4);
        protocol_read(32'h00010004,32'h55667788,4);
        protocol_read(32'h00020000,32'h01a5f00d,2);
        protocol_read(32'h00020100,32'h10203040,2);
        protocol_read(32'h00020104,32'h50607080,2);
        protocol_read(32'h00020108,32'h90a0b0c0,2);
        protocol_read(32'h00040010,32'h00000099,2);
        protocol_read(32'h00040014,32'h13572468,2);

        // Cancel at each incomplete memory-read edge, including the edge at
        // which the backend data is available but the response is not latched.
        for(integer phase=1;phase<=3;phase++) begin
            @(negedge clk);host_en=1;host_we=0;host_addr=0;
            repeat(phase) @(negedge clk);
            protocol_release();
            repeat(3) begin @(negedge clk);#1;if(host_ready!==0) $fatal(1,"Canceled host response escaped");end
            protocol_read(0,32'h13579bdf,4);
            protocol_cancels++;
        end
        for(integer phase=1;phase<=3;phase++) begin
            @(negedge clk);host_en=1;host_we=0;host_addr=0;
            repeat(phase) @(negedge clk);
            host_addr=4;
            protocol_wait(32'h2468ace0,4);
            protocol_release();
            protocol_cancels++;
        end
        // A completed read can be replaced without an idle cycle; the full
        // address tag must reject both a new lane and an out-of-window alias.
        @(negedge clk);host_en=1;host_we=0;host_addr=0;
        protocol_wait(32'h13579bdf,4);
        host_addr=4;
        protocol_wait(32'h2468ace0,4);
        host_addr=32'h80000004;
        repeat(3) begin #1;if(host_ready!==0) $fatal(1,"Aliased host address accepted");@(negedge clk);end
        protocol_release();protocol_cancels++;
        // A write immediately replaces a pending read. The write must use its
        // own current address rather than the canceled read's registered tag.
        for(integer phase=1;phase<=3;phase++) begin
            @(negedge clk);host_en=1;host_we=0;host_addr=0;
            repeat(phase) @(negedge clk);
            host_we=1;host_addr=4;host_wdata=32'habcdef00+phase;
            #1;if(host_ready!==1) $fatal(1,"Read-to-write switch changed write acceptance");
            @(negedge clk);protocol_release();
            protocol_read(0,32'h13579bdf,4);
            protocol_read(4,32'habcdef00+phase,4);
            protocol_cancels++;
        end
        @(negedge clk);host_en=1;host_we=0;host_addr=0;
        repeat(3) @(negedge clk);rst_n=0;
        #1;if(host_ready!==0 || host_rdata!==0) $fatal(1,"Reset did not cancel host response");
        @(negedge clk);rst_n=1;
        protocol_wait(32'h13579bdf,4);
        protocol_release();protocol_cancels++;

        // A long NOP program keeps the core active during host arbitration.
        for(integer index=0;index<32;index++) host_write(32'h00030000+index*4,0,1);
        host_write(32'h00030080,32'h00001e00,1);
        protocol_read(32'h00030080,32'h00001e00,4);
        host_write(32'h00040000,1,1);
        if(!running) $fatal(1,"Host protocol program did not start");
        for(integer region=0;region<4;region++) begin
            @(negedge clk);host_en=1;host_we=0;host_addr=blocked_addresses[region];
            repeat(5) begin
                #1;if(!running || host_ready!==0) $fatal(1,"Host memory/descriptor access accepted while running");
                @(negedge clk);
            end
            protocol_release();protocol_blocked++;
        end
        host_write(0,32'hbad00000,0);
        host_write(32'h00040010,32'h00000001,0);
        @(negedge clk);host_en=1;host_we=0;host_addr=32'h00040000;
        protocol_wait(1,2);
        clocks=0;
        while(running && clocks<512) begin @(negedge clk);clocks++;end
        if(running) $fatal(1,"Host protocol program timeout");
        #1;if(host_ready!==1 || host_rdata!==1) $fatal(1,"Held control read did not retain its first snapshot");
        protocol_release();
        protocol_read(32'h00040000,2,2);
        protocol_read(0,32'h13579bdf,4);
        protocol_read(32'h00040010,32'h00000080,2);
    endtask

    logic [23:0] quant_selector_den;
    task automatic check_quant_selector(input logic [23:0] denominator);
        logic [127:0] limit, numerator;
        logic [5:0] expected;
        bit found;
        limit=128'(denominator)*128'hffffff;
        expected=0;found=0;
        for(integer shift=47;shift>=0;shift--) begin
            numerator=128'd127 << shift;
            if(!found && numerator<=limit) begin expected=6'(shift);found=1;end
        end
        quant_selector_den=denominator;
        force dut.u_norm.u_norm.quant_den=quant_selector_den;
        #1;
        if(dut.u_norm.u_norm.quant_r_sel!==expected)
            $fatal(1,"QUANT selector den=%h expected=%0d",denominator,expected);
        release dut.u_norm.u_norm.quant_den;
        quant_selector_checks++;
    endtask
    initial begin
        check_quant_selector(0);
        for(integer bit_index=0;bit_index<24;bit_index++) begin
            for(integer offset=-1;offset<=1;offset++)
                check_quant_selector(24'((128'd1<<bit_index)+offset));
            if(bit_index>=7)
                for(integer offset=-1;offset<=1;offset++)
                    check_quant_selector(24'((128'd127<<(bit_index-6))+offset));
        end
        repeat(4096) check_quant_selector($urandom);
        check_host_protocol();
        fd=$fopen("tests/sim/host_vectors.txt","r");
        if(fd==0) $fatal(1,"Missing host vectors");
        while(!$feof(fd)) begin
            rc=$fscanf(fd,"%h %h %h %h",op,a,b,c);
            if(rc==4) begin
                case(op)
                    0: begin @(negedge clk);rst_n=0;host_en=0;host_we=0;repeat(3) @(negedge clk);rst_n=1;end
                    1: host_write(a,b,1);
                    2: host_check(a,b,c);
                    3: begin
                        count=0;
                        while(running && count<a) begin @(negedge clk);count=count+1;end
                        if(running) $fatal(1,"TIMEOUT case=%0d pc=%0d instr=%h",case_id,pc_debug,instr_debug);
                        host_check(32'h40000,b,c);
                    end
                    6: host_write(a,b,0);
                    7: begin case_id=a;cases_run=cases_run+1;$display("CASE %0d",case_id);end
                    8: begin
                        count=0;
                        while(!dut.u_norm.u_norm.div_busy && count<a) begin
                            @(negedge clk);count=count+1;
                        end
                        if(!dut.u_norm.u_norm.div_busy || !running)
                            $fatal(1,"NORM reset checkpoint was not reached case=%0d",case_id);
                        rst_n=0;host_en=0;host_we=0;
                        #1;if(running || !ready || error || overflow_out)
                            $fatal(1,"NORM reset did not clear control state");
                        repeat(3) @(negedge clk);rst_n=1;
                    end
                    default: $fatal(1,"Unknown test command");
                endcase
            end else if(!$feof(fd)) $fatal(1,"Malformed vectors");
        end
        $fclose(fd);$display("HOST_PASS cases=%0d protocol_reads=%0d protocol_cancels=%0d blocked_regions=%0d quant_selector=%0d",cases_run,protocol_reads,protocol_cancels,protocol_blocked,quant_selector_checks);$finish;
    end
    initial begin #1000000000;$fatal(1,"GLOBAL_TIMEOUT");end
endmodule

// Divider parameter profiles exercise truncation/extension independently of NPU widths.
module tb_div_case #(parameter int NUM_W=64,DEN_W=64)(output logic complete=0);
    logic clk=0,rst_n=0,start=0,busy,done,div_zero;
    logic [NUM_W-1:0] numerator=0,quotient;
    logic [DEN_W-1:0] denominator=0,remainder;
    integer checks=0;
    always #5 clk=~clk;
    div #(.NUM_W(NUM_W),.DEN_W(DEN_W)) dut(.*);
    task automatic check(input logic [NUM_W-1:0] a,input logic [DEN_W-1:0] b);
        logic [127:0] expected_q,expected_r;
        integer wait_cycles;
        @(negedge clk);numerator=a;denominator=b;start=1;
        @(negedge clk);start=0;numerator=~a;denominator=0;wait_cycles=0;
        while(!done && wait_cycles<=NUM_W) begin
            start=(wait_cycles==0 && NUM_W>1);
            @(negedge clk);start=0;wait_cycles++;
        end
        if(!done || busy) $fatal(1,"DIV profile timeout NUM=%0d DEN=%0d",NUM_W,DEN_W);
        if(b==0) begin
            if(!div_zero || quotient!=='1 || remainder!==DEN_W'(a))
                $fatal(1,"DIV profile zero contract NUM=%0d DEN=%0d a=%h",NUM_W,DEN_W,a);
        end else begin
            expected_q=128'(a)/128'(b);expected_r=128'(a)%128'(b);
            if(div_zero || quotient!==NUM_W'(expected_q) || remainder!==DEN_W'(expected_r) ||
               128'(quotient)*128'(b)+128'(remainder)!=128'(a) || 128'(remainder)>=128'(b))
                $fatal(1,"DIV profile mismatch NUM=%0d DEN=%0d a=%h b=%h",NUM_W,DEN_W,a,b);
        end
        checks++;
    endtask
    initial begin
        repeat(2) @(negedge clk);rst_n=1;
        if(NUM_W<=7 && DEN_W<=7) begin
            for(integer a=0;a<(1<<NUM_W);a++)
                for(integer b=0;b<(1<<DEN_W);b++) check(NUM_W'(a),DEN_W'(b));
        end else begin
            check(0,0);check(0,1);check('1,0);check('1,1);check('1,'1);check(1,'1);
            repeat(128) check(NUM_W'({$urandom,$urandom}),DEN_W'({$urandom,$urandom}));
        end
        $display("DIV_PROFILE_PASS NUM=%0d DEN=%0d checks=%0d",NUM_W,DEN_W,checks);
        complete=1;
    end
endmodule

module tb_divprofiles;
    wire [4:0] complete;
    tb_div_case #(.NUM_W(1),.DEN_W(1)) div_1_1(complete[0]);
    tb_div_case #(.NUM_W(7),.DEN_W(3)) div_7_3(complete[1]);
    tb_div_case #(.NUM_W(3),.DEN_W(7)) div_3_7(complete[2]);
    tb_div_case #(.NUM_W(64),.DEN_W(32)) div_64_32(complete[3]);
    tb_div_case #(.NUM_W(64),.DEN_W(64)) div_64_64(complete[4]);
    initial begin wait(&complete);$display("DIVPROFILES_PASS profiles=5");$finish;end
    initial begin #10000000;$fatal(1,"DIVPROFILES_TIMEOUT");end
endmodule

module tb_postscale;
    logic signed [17:0] acc=0;
    logic [23:0] scale_m=0;
    logic [5:0] scale_r=0;
    logic signed [31:0] bias=0,y_s32;
    logic output_s32=0,overflow;
    logic signed [15:0] y_s16;
    integer checks=0;
    integer acc_edges[0:8]='{-131072,-131071,-3,-1,0,1,3,131070,131071};
    integer scale_edges[0:5]='{0,1,2,127,128,16777215};
    integer shift_edges[0:9]='{0,1,2,17,23,24,41,42,47,63};
    integer bias_edges[0:8]='{-2147483648,-32769,-32768,-1,0,1,32767,32768,2147483647};
    postscale dut(.*);
    task automatic check;
        logic signed [127:0] value,rounded,biased;
        logic [127:0] magnitude,denominator,quotient,remainder;
        logic signed [31:0] expected_s32;
        logic signed [15:0] expected_s16;
        bit expected_overflow;
        value=128'($signed(acc))*$signed({104'h0,scale_m});
        magnitude=value<0 ? -value : value;
        denominator=128'd1 << scale_r;
        quotient=magnitude/denominator;remainder=magnitude%denominator;
        if(2*remainder>denominator || (2*remainder==denominator && quotient[0])) quotient++;
        rounded=value<0 ? -$signed(quotient) : $signed(quotient);
        biased=rounded+128'($signed(bias));
        expected_s32=biased>2147483647 ? 32'sh7fffffff : biased< -128'sd2147483648 ? 32'sh80000000 : 32'(biased);
        expected_s16=biased>32767 ? 16'sh7fff : biased< -32768 ? 16'sh8000 : 16'(biased);
        expected_overflow=output_s32 ? (biased>2147483647 || biased< -128'sd2147483648) : (biased>32767 || biased< -32768);
        #1;
        if(y_s32!==expected_s32 || y_s16!==expected_s16 || overflow!==expected_overflow)
            $fatal(1,"POSTSCALE mismatch acc=%0d m=%h r=%0d bias=%0d s32=%b",$signed(acc),scale_m,scale_r,$signed(bias),output_s32);
        checks++;
    endtask
    initial begin
        for(integer a=0;a<9;a++)
            for(integer m=0;m<6;m++)
                for(integer r=0;r<10;r++)
                    for(integer b=0;b<9;b++)
                        for(integer f=0;f<2;f++) begin
                            acc=18'(acc_edges[a]);scale_m=24'(scale_edges[m]);scale_r=6'(shift_edges[r]);
                            bias=32'(bias_edges[b]);output_s32=f;check();
                        end
        repeat(3000) begin
            acc=$urandom;scale_m=$urandom;scale_r=$urandom;bias=$urandom;output_s32=$urandom;
            check();
        end
        $display("POSTSCALE_PASS checks=%0d",checks);$finish;
    end
    initial begin #1000000;$fatal(1,"POSTSCALE_TIMEOUT");end
endmodule

// tb_scalar.sv
`timescale 1ns/1ps
module tb_scalar;
    import npu_pkg::*;
    logic clk=0,rst_n=0,start=0,busy,done,dz;
    logic [63:0] n=0,d=0,q,r;
    logic ss=0,sb,sd;logic [31:0] root;
    logic cs=0,cb,cd,ce;logic [23:0] fm=0,qd=0,cm;logic [5:0] fr=0,cr;
    integer rne_checks=0,div_checks=0,sqrt_checks=0,compose_checks=0,compose_max_cycles=0;
    logic signed [63:0] random_rne;
    logic [63:0] square_boundary;
    logic [31:0] root_boundary;
    logic [127:0] coefficient_boundary;
    integer coefficient_edges[0:8]='{0,1,2,126,127,128,65536,8388607,16777215};
    integer denominator_edges[0:5]='{1,2,3,127,65536,16777215};
    integer coefficient_shifts[0:10]='{0,1,2,15,23,24,31,46,47,48,63};
    div #(.NUM_W(64),.DEN_W(64)) u_div(.clk(clk),.rst_n(rst_n),.start(start),.numerator(n),.denominator(d),.busy(busy),.done(done),.div_zero(dz),.quotient(q),.remainder(r));
    isqrt_u64 u_sqrt(.clk(clk),.rst_n(rst_n),.start(ss),.radicand(n),.busy(sb),.done(sd),.root(root));
    scale_compose u_compose(.clk(clk),.rst_n(rst_n),.start(cs),.factor_m(fm),.factor_r(fr),.quant_d(qd),.busy(cb),.done(cd),.format_error(ce),.result_m(cm),.result_r(cr));
    always #5 clk=~clk;
    task automatic check_div(input logic [63:0] a,b);
        integer wait_cycles;
        @(negedge clk);n=a;d=b;start=1;@(negedge clk);start=0;
        n=~a;d=0;wait_cycles=0;
        while(!done && wait_cycles<65) begin
            start=(wait_cycles==0);
            @(negedge clk);start=0;wait_cycles++;
        end
        if(!done || busy) $fatal(1,"DIV response timeout/status");
        if(b==0) begin if(!dz || q!=='1 || r!==a) $fatal(1,"divide-by-zero contract");end
        else if(dz || q!==a/b || r!==a%b) $fatal(1,"DIV mismatch a=%h b=%h",a,b);
        div_checks++;
    endtask
    task automatic check_sqrt(input logic [63:0] a);
        logic [65:0] square,next_square;
        integer wait_cycles;
        @(negedge clk);n=a;ss=1;@(negedge clk);ss=0;n=~a;wait_cycles=0;
        while(!sd && wait_cycles<33) begin
            ss=(wait_cycles==0);
            @(negedge clk);ss=0;wait_cycles++;
        end
        if(!sd || sb || wait_cycles!=32) $fatal(1,"SQRT response latency/status clocks=%0d",wait_cycles);
        square=66'(root)*66'(root);next_square=(66'(root)+1)*(66'(root)+1);
        if(square>a || next_square<=a) $fatal(1,"SQRT mismatch a=%h root=%h",a,root);
        sqrt_checks++;
    endtask
    task automatic check_compose(input logic [23:0] m,den,input logic [5:0] shift);
        logic [127:0] ref_n,ref_d,ref_q,ref_rem,ref_rounded;
        logic [23:0] expected_m;
        logic [5:0] expected_r;
        bit fail,found;
        integer wait_cycles;
        expected_m=0;expected_r=0;found=0;
        fail=(den==0 || shift>47);
        if(!fail && m!=0) begin
            ref_d=128'd8323072 << shift;
            for(integer candidate=47;candidate>=0;candidate--) begin
                ref_n=(128'(m)*128'(den)) << candidate;
                ref_q=ref_n/ref_d;ref_rem=ref_n%ref_d;
                ref_rounded=ref_q+((2*ref_rem>ref_d) || (2*ref_rem==ref_d && ref_q[0]));
                if(!found && ref_rounded>0 && ref_rounded<=128'hffffff) begin
                    expected_m=ref_rounded[23:0];expected_r=6'(candidate);found=1;
                end
            end
            fail=!found;
        end
        @(negedge clk);fm=m;qd=den;fr=shift;cs=1;@(negedge clk);cs=0;
        fm=0;qd=0;fr=63;wait_cycles=0;
        while(!cd && wait_cycles<200) begin
            cs=(wait_cycles==0);
            @(negedge clk);cs=0;wait_cycles++;
        end
        if(!cd || cb) $fatal(1,"COMPOSE response timeout/status");
        if(ce!==fail) $fatal(1,"COMPOSE error flag m=%h d=%h r=%0d",m,den,shift);
        if(cm!==expected_m || cr!==expected_r)
            $fatal(1,"COMPOSE mismatch m=%h d=%h r=%0d expected=%h/%0d actual=%h/%0d",m,den,shift,expected_m,expected_r,cm,cr);
        if(!fail && wait_cycles>128) $fatal(1,"COMPOSE exceeded one-division latency clocks=%0d",wait_cycles);
        if(!fail && wait_cycles>compose_max_cycles) compose_max_cycles=wait_cycles;
        compose_checks++;
    endtask
    task automatic check_scalar_reset;
        @(negedge clk);n='1;d=3;start=1;ss=1;fm=1;qd=1;fr=0;cs=1;
        @(negedge clk);start=0;ss=0;cs=0;
        repeat(8) @(negedge clk);
        rst_n=0;
        #1;if(busy || done || dz || sb || sd || cb || cd || ce || q!==0 || r!==0 || root!==0 || cm!==0 || cr!==0)
            $fatal(1,"Scalar reset did not cancel pending transactions");
        repeat(2) @(negedge clk);rst_n=1;
        repeat(70) begin
            @(negedge clk);
            if(busy || done || sb || sd || cb || cd) $fatal(1,"Aborted scalar response escaped reset");
        end
        check_div(123,7);check_sqrt('1);check_compose(127,65536,0);
    endtask
    task automatic check_rne(input logic signed [63:0] value,input logic [5:0] shift);
        logic signed [127:0] wide,expected;
        logic [127:0] magnitude,divisor,quotient,remainder;
        wide={{64{value[63]}},value};
        magnitude=value[63] ? -wide : wide;
        divisor=128'd1 << shift;
        quotient=magnitude/divisor;
        remainder=magnitude%divisor;
        if(2*remainder>divisor || (2*remainder==divisor && quotient[0])) quotient=quotient+1;
        expected=value[63] ? -$signed(quotient) : $signed(quotient);
        if(rne_shift64(value,shift)!==expected[63:0])
            $fatal(1,"RNE mismatch x=%h shift=%0d expected=%h",value,shift,expected[63:0]);
        rne_checks=rne_checks+1;
    endtask
    initial begin
        repeat(2) @(negedge clk);rst_n=1;
        if(rne_shift64(-64'sd5,1)!==-64'sd2 || rne_shift64(-64'sd7,1)!==-64'sd4 ||
           rne_shift64(64'sd5,1)!==64'sd2 || rne_shift64(64'sd7,1)!==64'sd4 ||
           rne_shift64(64'sh8000000000000000,63)!==-64'sd1) $fatal(1,"RNE edge");
        for(integer shift=0;shift<64;shift=shift+1) begin
            check_rne(0,6'(shift));check_rne(1,6'(shift));check_rne(-1,6'(shift));
            check_rne(64'sh8000000000000000,6'(shift));check_rne(64'sh7fffffffffffffff,6'(shift));
            for(integer value=-256;value<256;value=value+1) check_rne(64'(value),6'(shift));
        end
        for(integer sample=0;sample<64;sample=sample+1) begin
            random_rne={$urandom,$urandom};
            for(integer shift=0;shift<64;shift=shift+1) check_rne(random_rne,6'(shift));
        end
        check_div(0,1);check_div('1,1);check_div('1,'1);check_div('1,64'h8000000000000001);check_div(17,0);
        check_sqrt(0);check_sqrt(1);check_sqrt(2);check_sqrt('1);check_sqrt(64'h4000000000000000);
        for(integer a=0;a<4096;a++) check_sqrt(64'(a));
        for(integer bit_index=0;bit_index<32;bit_index++) begin
            root_boundary=32'd1 << bit_index;
            square_boundary=64'(root_boundary)*64'(root_boundary);
            check_sqrt(square_boundary-1);check_sqrt(square_boundary);check_sqrt(square_boundary+1);
        end
        root_boundary='1;square_boundary=64'(root_boundary)*64'(root_boundary);
        check_sqrt(square_boundary-1);check_sqrt(square_boundary);check_sqrt(square_boundary+1);
        for(integer i=0;i<100;i=i+1) begin
            check_div({$urandom,$urandom},{$urandom,$urandom}|1);
            check_sqrt({$urandom,$urandom});
        end
        check_compose(0,1,0);check_compose(1,1,0);check_compose(24'hffffff,24'hffffff,0);
        check_compose(1,1,47);check_compose(1,0,0);check_compose(1,1,48);
        check_compose(9846783,14181074,47);check_compose(9846784,14181074,47);check_compose(9846785,14181074,47);
        check_compose(24'hffffff,24'hffffff,47);
        for(integer i=0;i<9;i++)
            for(integer j=0;j<6;j++)
                for(integer k=0;k<11;k++)
                    check_compose(24'(coefficient_edges[i]),24'(denominator_edges[j]),6'(coefficient_shifts[k]));
        // Probe both sides of the odd-U24 RNE limit at every reachable candidate.
        for(integer candidate=24;candidate<=47;candidate++) begin
            coefficient_boundary=(128'd8323072*((128'd1<<25)-1)) >> (candidate+1);
            for(integer offset=-1;offset<=2;offset++)
                if($signed(coefficient_boundary)+offset>=0)
                    check_compose(24'($signed(coefficient_boundary)+offset),1,0);
        end
        repeat(200) check_compose($urandom,$urandom|1,6'($urandom_range(0,47)));
        check_scalar_reset();
        $display("SCALAR_PASS division=%0d sqrt=%0d RNE=%0d coefficients=%0d compose_max_clocks=%0d protocol=reset_and_busy_start",div_checks,sqrt_checks,rne_checks+5,compose_checks,compose_max_cycles);$finish;
    end
    initial begin #10000000;$fatal(1,"SCALAR_TIMEOUT");end
endmodule

// tb_sigmoid.sv
`timescale 1ns/1ps
module tb_sigmoid;
    logic clk=0,rst_n=0,start=0,busy,done;
    logic signed [15:0] x_raw=0;
    logic [4:0] frac_bits=0;
    logic [15:0] y_raw;
    logic [15:0] expected[0:1638399];
    integer index=0,timeout;
    always #5 clk=~clk;
    sigmoid dut(.*);
    initial begin
        $readmemh("tests/sim/sigmoid_expected.mem",expected);
        repeat(2) @(negedge clk);rst_n=1;
        for(integer f=0;f<25;f=f+1) begin
            for(integer x=-32768;x<32768;x=x+1) begin
                @(negedge clk);x_raw=x;frac_bits=f;start=1;
                @(negedge clk);start=0;
                // Inputs may change immediately after the start transaction.
                x_raw=16'sh5a5a;frac_bits=0;timeout=0;
                while(!done && timeout<10) begin @(negedge clk);timeout=timeout+1;end
                if(!done || y_raw!==expected[index])
                    $fatal(1,"SIG f=%0d x=%0d expected=%h got=%h",f,x,expected[index],y_raw);
                index=index+1;
            end
        end
        // Cancel a request during ROM lookup, then verify a fresh transaction.
        @(negedge clk);x_raw=0;frac_bits=15;start=1;
        @(negedge clk);start=0;
        @(negedge clk);rst_n=0;
        #1;if(busy || done || y_raw!==0) $fatal(1,"SIG reset state");
        @(negedge clk);rst_n=1;
        repeat(5) begin @(negedge clk);if(done || busy) $fatal(1,"SIG aborted response");end
        @(negedge clk);x_raw=0;frac_bits=15;start=1;
        @(negedge clk);start=0;x_raw=32767;frac_bits=0;
        @(negedge clk);start=1; // The captured x=0 request remains in flight.
        @(negedge clk);start=0;timeout=0;
        while(!done && timeout<10) begin @(negedge clk);timeout++;end
        if(!done || y_raw!==16'h4000) $fatal(1,"SIG busy start/input capture");
        // Cancel in every registered phase, then demand a fresh correct result.
        for(integer phase=1;phase<=6;phase++) begin
            @(negedge clk);x_raw=-16384;frac_bits=12;start=1;
            @(negedge clk);start=0;
            repeat(phase-1) @(negedge clk);
            rst_n=0;#1;
            if(busy || done || y_raw!==0) $fatal(1,"SIG pipeline reset phase=%0d",phase);
            @(negedge clk);rst_n=1;
            repeat(8) begin @(negedge clk);if(done || busy) $fatal(1,"SIG stale pipeline response phase=%0d",phase);end
            @(negedge clk);x_raw=0;frac_bits=12;start=1;
            @(negedge clk);start=0;timeout=0;
            while(!done && timeout<10) begin @(negedge clk);timeout++;end
            if(!done || busy || y_raw!==16'h4000) $fatal(1,"SIG restart phase=%0d",phase);
        end
        $display("SIGMOID_PASS cases=%0d formats=25 protocol_checks=2 pipeline_reset_phases=6",index);$finish;
    end
endmodule

// tb_sram.sv
`timescale 1ns/1ps
module tb_sram;
    localparam int ADDR_W = 2;
    logic clk = 0;
    logic rst_n = 0;
    logic rd_en = 0, wr_en = 0, host_en = 0, host_we = 0;
    logic [ADDR_W - 1 : 0] rd_addr = 0, wr_addr = 0;
    logic [255:0] rd_data, wr_data = 0;
    logic rd_valid, host_rvalid;
    logic [ADDR_W + 2 : 0] host_addr = 0;
    logic [31:0] host_wdata = 0, host_rdata;
    logic [255:0] expected [0:3];
    integer checks = 0;

    always #5 clk = ~clk;
    sram_256_wrapper #(.ADDR_W(ADDR_W)) dut(.*);

    task automatic check_host(input logic [ADDR_W + 2 : 0] address);
        @(negedge clk);
        host_en = 1;
        host_we = 0;
        host_addr = address;
        #1;
        if (host_rvalid !== 0)
            $fatal(1, "Stale host response accepted at address %0d", address);
        @(posedge clk);
        #1;
        if (host_rvalid !== 0)
            $fatal(1, "Host response arrived before two clocks");
        @(posedge clk);
        #1;
        if (host_rvalid !== 1 ||
            host_rdata !== expected[address[ADDR_W + 2 : 3]][address[2:0] * 32 +: 32])
            $fatal(1, "Host read mismatch at address %0d: %h", address, host_rdata);
        checks = checks + 1;
    endtask

    task automatic release_host;
        @(negedge clk);
        host_en = 0;
        #1;
        if (host_rvalid !== 0)
            $fatal(1, "Host valid remained asserted without a request");
    endtask

    task automatic check_compute(input logic [ADDR_W - 1 : 0] address);
        @(negedge clk);
        rd_en = 1;
        rd_addr = address;
        @(posedge clk);
        #1;
        if (rd_valid !== 0)
            $fatal(1, "Compute response arrived before two clocks");
        @(negedge clk);
        rd_en = 0;
        @(posedge clk);
        #1;
        if (rd_valid !== 1 || rd_data !== expected[address])
            $fatal(1, "Compute read mismatch at row %0d", address);
        @(posedge clk);
        #1;
        if (rd_valid !== 0)
            $fatal(1, "Compute valid repeated without another request");
        checks = checks + 1;
    endtask

    initial begin
        repeat (2) @(negedge clk);
        rst_n = 1;
        for (int row = 0; row < 4; row++) begin
            for (int lane = 0; lane < 8; lane++)
                expected[row][lane * 32 +: 32] = 32'ha500_0000 + row * 256 + lane;
            @(negedge clk);
            wr_en = 1;
            wr_addr = ADDR_W'(row);
            wr_data = expected[row];
            @(negedge clk);
            wr_en = 0;
        end

        // Keep host_en high while changing lanes and rows. This catches a
        // previous response incorrectly acknowledging the next address.
        for (int address = 0; address < 32; address++)
            check_host((ADDR_W + 3)'(address));

        // A read/write/read sequence to the same address must not reuse the
        // response captured before the write, even when host_en stays high.
        @(negedge clk);
        host_we = 1;
        host_wdata = 32'hcafe_1234;
        expected[3][7 * 32 +: 32] = host_wdata;
        check_host(5'd31);
        release_host();

        // Host lane writes must preserve all other lanes in the 256-bit row.
        for (int lane = 0; lane < 8; lane++) begin
            @(negedge clk);
            host_en = 1;
            host_we = 1;
            host_addr = (ADDR_W + 3)'(8 + lane);
            host_wdata = 32'h5a00_0000 + lane;
            expected[1][lane * 32 +: 32] = host_wdata;
            @(negedge clk);
            host_en = 0;
            host_we = 0;
        end
        for (int row = 0; row < 4; row++)
            check_compute(ADDR_W'(row));
        for (int address = 8; address < 16; address++)
            check_host((ADDR_W + 3)'(address));
        release_host();

        // Reset clears response validity while retaining SRAM contents.
        @(negedge clk);
        rst_n = 0;
        #1;
        if (host_rvalid !== 0 || rd_valid !== 0)
            $fatal(1, "Response valid during reset");
        repeat (2) @(negedge clk);
        rst_n = 1;
        check_compute(2'd1);
        check_host(5'd15);
        release_host();
        $display("SRAM_PASS checks=%0d", checks);
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "SRAM_TIMEOUT");
    end
endmodule

// Retained arithmetic boundary/random coverage, adapted to the main interfaces.
`timescale 1ns/1ps
module tb_acc_case #(parameter int N=32)(output logic complete=0);
    logic signed [8:0] term[N-1:0];
    logic signed [17:0] sum;
    integer expected;
    acc_mul #(.TERM_W(9),.NUM_INPUTS(N),.ACC_W(18)) dut(.*);

    task automatic check_sum(input integer pattern);
        expected=0;
        for(integer lane=0;lane<N;lane++) begin
            case(pattern)
                0: term[lane]=0;
                1: term[lane]=255;
                2: term[lane]=-256;
                3: term[lane]=lane%2 ? 255 : -256;
                default: term[lane]=$urandom_range(0,511)-256;
            endcase
            expected=expected+$signed(term[lane]);
        end
        #1;
        if($signed(sum)!==expected)
            $fatal(1,"ACC mismatch N=%0d expected=%0d actual=%0d",N,expected,$signed(sum));
    endtask

    initial begin
        for(integer pattern=0;pattern<4;pattern++) check_sum(pattern);
        repeat(1000) check_sum(4);
        complete=1;
    end
endmodule

module tb_arithmetic;
    parameter string BLOCK="all";
    logic signed [15:0] a=0,b=0;
    logic sub=0,b_unsigned=0;
    logic [5:0] rshift=0;
    logic signed [16:0] wide;
    logic signed [15:0] add_result,mul_result;
    logic signed [31:0] product;
    logic add_overflow,mul_overflow;
    wire [4:0] complete;
    integer add_checks=0,mul_checks=0;
    integer edges[0:10]='{-32768,-32767,-7,-5,-1,0,1,5,7,32766,32767};
    integer shifts[0:5]='{0,1,15,31,47,63};

    addsub u_add(.a(a),.b(b),.sub(sub),.wide(wide),.result(add_result),.overflow(add_overflow));
    mul u_mul(.a(a),.b(b),.b_unsigned(b_unsigned),.rshift(rshift),.product(product),.result(mul_result),.overflow(mul_overflow));
    tb_acc_case #(.N(1)) acc_1(complete[0]);
    tb_acc_case #(.N(3)) acc_3(complete[1]);
    tb_acc_case #(.N(32)) acc_32(complete[2]);
    tb_acc_case #(.N(37)) acc_37(complete[3]);
    tb_acc_case #(.N(512)) acc_512(complete[4]);

    function automatic longint signed round_even(input longint signed value,input integer shift);
        longint unsigned magnitude,denominator,quotient,remainder;
        if(shift==0) return value;
        magnitude=value<0 ? -value : value;
        denominator=64'd1<<shift;
        quotient=magnitude/denominator;
        remainder=magnitude%denominator;
        if(2*remainder>denominator || (2*remainder==denominator && quotient[0])) quotient++;
        return value<0 ? -$signed(quotient) : $signed(quotient);
    endfunction

    function automatic integer clamp16(input longint signed value);
        return value>32767 ? 32767 : value< -32768 ? -32768 : integer'(value);
    endfunction

    task automatic check_add;
        integer expected;
        expected=integer'($signed(a))+(sub ? -integer'($signed(b)) : integer'($signed(b)));
        #1;
        if($signed(wide)!==expected || $signed(add_result)!==clamp16(expected) ||
           add_overflow!==(expected>32767 || expected< -32768))
            $fatal(1,"ADDSUB mismatch a=%0d b=%0d sub=%b",$signed(a),$signed(b),sub);
        add_checks++;
    endtask

    task automatic test_addsub;
        for(integer s=0;s<2;s++)
            for(integer i=0;i<11;i++)
                for(integer j=0;j<11;j++) begin a=edges[i];b=edges[j];sub=s;check_add();end
        repeat(3000) begin a=$urandom;b=$urandom;sub=$urandom_range(0,1);check_add();end
    endtask

    task automatic check_mul;
        longint signed expected_product,rounded;
        expected_product=longint'($signed(a))*(b_unsigned ? longint'($unsigned(b)) : longint'($signed(b)));
        rounded=round_even(expected_product,integer'(rshift));
        #1;
        if($signed(product)!==expected_product || $signed(mul_result)!==clamp16(rounded) ||
           mul_overflow!==(rounded>32767 || rounded< -32768 || (b_unsigned && $unsigned(b)>32768)))
            $fatal(1,"MUL mismatch a=%0d b=%h unsigned=%b shift=%0d",$signed(a),b,b_unsigned,rshift);
        mul_checks++;
    endtask

    task automatic test_mul;
        for(integer u=0;u<2;u++)
            for(integer i=0;i<11;i++)
                for(integer j=0;j<11;j++)
                    for(integer s=0;s<6;s++) begin
                        a=edges[i];b=edges[j];b_unsigned=u;rshift=shifts[s];check_mul();
                    end
        repeat(3000) begin a=$urandom;b=$urandom;b_unsigned=$urandom_range(0,1);rshift=$urandom_range(0,63);check_mul();end
    endtask

    task automatic test_accmul;
        wait(&complete);
    endtask

    initial begin
        if(BLOCK!="all" && BLOCK!="accmul" && BLOCK!="addsub" && BLOCK!="mul") $fatal(1,"Invalid arithmetic block");
        if(BLOCK=="all" || BLOCK=="addsub") test_addsub();
        if(BLOCK=="all" || BLOCK=="mul") test_mul();
        if(BLOCK=="all" || BLOCK=="accmul") test_accmul();
        $display("ARITHMETIC_PASS block=%s addsub=%0d mul=%0d accumulator_profiles=5",BLOCK,add_checks,mul_checks);
        $finish;
    end
    initial begin #1000000;$fatal(1,"ARITHMETIC_TIMEOUT");end
endmodule

// Instruction storage: all 512 words, class/address tags and restart/reset.
module tb_imem;
    logic clk=0,rst_n=0,fetch_en=0,host_en=0,host_we=0;
    logic [8:0] addr=0,host_addr=0;
    logic [12:0] instr,host_instr=0,host_rinstr;
    logic instr_valid,host_rvalid;
    logic [12:0] expected[0:511];
    integer checks=0;
    always #5 clk=~clk;
    ins_mem dut(.*);

    task automatic read_word(input bit host,input logic [8:0] address);
        @(negedge clk);
        host_en=host;host_we=0;fetch_en=!host;
        if(host) host_addr=address;else addr=address;
        #1;
        if((host ? host_rvalid : instr_valid)!==0) $fatal(1,"Stale instruction response");
        @(posedge clk);#1;
        if((host ? host_rvalid : instr_valid)!==0) $fatal(1,"Instruction read before two clocks");
        @(posedge clk);#1;
        if((host ? host_rvalid : instr_valid)!==1 ||
           (host ? host_rinstr : instr)!==expected[address])
            $fatal(1,"Instruction read mismatch host=%b addr=%0d",host,address);
        if((host ? instr_valid : host_rvalid)!==0) $fatal(1,"Instruction valid sent to wrong client");
        checks=checks+1;
    endtask

    initial begin
        repeat(2) @(negedge clk);rst_n=1;
        for(integer address=0;address<512;address=address+1) begin
            @(negedge clk);host_en=1;host_we=1;host_addr=9'(address);
            host_instr=13'((address*37)^13'h1234);expected[address]=host_instr;
        end
        for(integer address=0;address<512;address=address+1) read_word(1,9'(address));
        // Keep host enabled and overwrite/read the last address.
        @(negedge clk);host_we=1;host_instr=13'h1abc;expected[511]=host_instr;
        #1;if(host_rvalid!==0) $fatal(1,"Instruction valid during write");
        read_word(1,9'd511);
        // Switch to fetch without an idle gap, then change PC in reverse order.
        for(integer address=511;address>=0;address=address-1) read_word(0,9'(address));
        @(negedge clk);fetch_en=0;
        #1;if(instr_valid!==0) $fatal(1,"Fetch valid without enable");
        @(negedge clk);
        read_word(0,9'd0); // Restart at the same PC must acquire a fresh response.
        @(negedge clk);rst_n=0;
        #1;if(instr_valid!==0 || host_rvalid!==0) $fatal(1,"Instruction valid during reset");
        repeat(2) @(negedge clk);fetch_en=0;rst_n=1;
        read_word(1,9'd511); // Memory contents survive reset.
        $display("IMEM_PASS checks=%0d",checks);$finish;
    end
    initial begin #1000000;$fatal(1,"IMEM_TIMEOUT");end
endmodule

// Rowwise arithmetic uses an independent S128 reference, including ties,
// partial words and protocol cancellation of payload registers without reset.
module tb_rowwise;
    logic clk=0,rst_n=0,start=0;
    logic [3:0] select=0;
    logic [255:0] a_word=0,b_word=0,c_word=0,result_word;
    logic [4:0] a_frac_bits=0,b_frac_bits=0,dst_frac_bits=0,valid_elems=0;
    logic a_unsigned=0,b_unsigned=0,dst_unsigned=0;
    logic busy,done,overflow,format_error;
    integer checks=0,element_checks=0,busy_checks=0,reset_checks=0;
    integer operations[0:4]='{1,2,3,11,12};
    integer fractions[0:3]='{0,1,15,24};
    integer tails[0:3]='{1,3,15,16};
    integer edges[0:9]='{-32768,-32767,-5,-1,0,1,3,5,32766,32767};
    always #5 clk=~clk;
    rowwise_op dut(.*);

    function automatic logic signed [127:0] widen(input logic [15:0] value,input bit unsigned_input);
        return unsigned_input ? $signed({112'h0,value}) : $signed({{112{value[15]}},value});
    endfunction

    function automatic logic signed [127:0] scale_reference(
            input logic signed [127:0] value,input integer shift);
        logic [127:0] magnitude,denominator,quotient,remainder;
        if(shift<0) return value<<<(-shift);
        if(shift==0) return value;
        magnitude=value<0 ? $unsigned(-value) : $unsigned(value);
        denominator=128'h1<<shift;
        quotient=magnitude/denominator;
        remainder=magnitude%denominator;
        if(2*remainder>denominator || (2*remainder==denominator && quotient[0])) quotient++;
        return value<0 ? -$signed(quotient) : $signed(quotient);
    endfunction

    task automatic check_case(input integer operation,
            input logic [255:0] aw,bw,cw,input integer af,bf,df,n,
            input bit au,bu,du,tamper,input bit launch_now=0);
        logic [255:0] expected;
        logic signed [127:0] a,b,raw,scaled,old_state,candidate;
        logic [15:0] gate,complement;
        bit expected_overflow,expected_error,pair_error;
        integer stride,shift,clocks,checked;
        expected=0;expected_overflow=0;expected_error=0;checked=0;
        if(n==0 || n>16 || af>24 || bf>24 || df>24 ||
            !(operation==1 || operation==2 || operation==3 || operation==6 || operation==11 || operation==12)) expected_error=1;
        else begin
            stride=operation==11 ? 1 : 2;
            shift=operation==11 ? 15 : (operation==3 ? af+bf : af)-df;
            for(integer base=0;base<n;base+=stride) begin
                pair_error=0;
                for(integer lane=0;lane<stride && base+lane<n;lane++) begin
                    a=widen(aw[(base+lane)*16+:16],au);
                    b=widen(bw[(base+lane)*16+:16],bu);
                    if(operation!=12 && ((au && a>32768) || (bu && b>32768))) pair_error=1;
                    case(operation)
                        1: raw=a+b;
                        2: raw=a-b;
                        3: raw=a*b;
                        6: begin
                            if(aw[(base+lane)*16+:16]!==16'h0000) $fatal(1,"SIG smoke expects zero input");
                            raw=16384;
                        end
                        11: begin
                            old_state=widen(cw[base*16+:16],0);
                            candidate=widen(aw[base*16+:16],0);
                            gate=bw[base*16+:16];
                            complement=16'h8000-gate;
                            raw=old_state*$signed({112'h0,gate})+candidate*$signed({112'h0,complement});
                            pair_error=gate>16'h8000;
                        end
                        default: raw=a<0 ? 128'sh0 : a;
                    endcase
                    scaled=operation==6 ? raw : scale_reference(raw,shift);
                    if(du && operation!=12 && operation!=11 && operation!=6) begin
                        if(scaled<0) begin expected[(base+lane)*16+:16]=0;expected_overflow=1;end
                        else if(scaled>32768) begin expected[(base+lane)*16+:16]=16'h8000;expected_overflow=1;end
                        else expected[(base+lane)*16+:16]=16'(scaled);
                    end else begin
                        if(scaled>32767) begin expected[(base+lane)*16+:16]=16'h7fff;expected_overflow=1;end
                        else if(scaled< -128'sd32768) begin expected[(base+lane)*16+:16]=16'h8000;expected_overflow=1;end
                        else expected[(base+lane)*16+:16]=16'(scaled);
                    end
                    checked++;
                end
                if(operation==6) pair_error=0;
                if(pair_error) begin expected_error=1;break;end
            end
        end
        if(!launch_now) @(negedge clk);
        select=4'(operation);a_word=aw;b_word=bw;c_word=cw;
        a_frac_bits=5'(af);b_frac_bits=5'(bf);dst_frac_bits=5'(df);valid_elems=5'(n);
        a_unsigned=au;b_unsigned=bu;dst_unsigned=du;start=1;
        @(negedge clk);start=0;clocks=0;
        while(!done && clocks<256) begin
            if(tamper) begin
                select=4'hf;a_word=~aw;b_word=~bw;c_word=~cw;
                a_frac_bits=31;b_frac_bits=31;dst_frac_bits=31;valid_elems=0;
                a_unsigned=!au;b_unsigned=!bu;dst_unsigned=!du;start=1;
                busy_checks++;
            end
            @(negedge clk);clocks++;
        end
        start=0;
        if(!done || busy || result_word!==expected || overflow!==expected_overflow || format_error!==expected_error)
            $fatal(1,"ROWWISE op=%0d n=%0d frac=%0d/%0d/%0d unsigned=%0b%0b%0b clocks=%0d expected=%h actual=%h flags=%b%b expected_flags=%b%b",
                operation,n,af,bf,df,au,bu,du,clocks,expected,result_word,format_error,overflow,expected_error,expected_overflow);
        checks++;element_checks+=checked;
        @(negedge clk);
        if(done || busy || result_word!==expected || overflow!==expected_overflow || format_error!==expected_error)
            $fatal(1,"ROWWISE response did not remain stable after one-cycle done");
    endtask

    task automatic reset_phase(input integer phase);
        integer clocks;
        @(negedge clk);select=phase==6 ? 6 : 11;
        a_word={16{16'h7fff}};b_word={16{16'h4000}};c_word={16{16'h8000}};
        a_frac_bits=15;b_frac_bits=15;dst_frac_bits=15;valid_elems=3;
        a_unsigned=0;b_unsigned=0;dst_unsigned=0;start=1;
        @(negedge clk);start=0;clocks=0;
        while(integer'(dut.state)!=phase && clocks<20) begin @(negedge clk);clocks++;end
        if(integer'(dut.state)!=phase || !busy) $fatal(1,"ROWWISE reset phase was not reached: %0d",phase);
        rst_n=0;
        #1;if(busy || done || overflow || format_error || result_word!==256'h0)
            $fatal(1,"ROWWISE asynchronous reset failed in phase %0d",phase);
        @(negedge clk);rst_n=1;
        // A fresh request starts on the same edge that releases reset. The
        // canceled products must not leak into the new half-way result.
        check_case(3,{16{16'h0001}},{16{16'h0005}},0,1,0,0,3,0,0,0,1,1);
        reset_checks++;
    endtask

    initial begin
        logic [255:0] aw,bw,cw;
        integer operation,af,bf,df,n;
        bit au,bu,du;
        repeat(2) @(negedge clk);rst_n=1;
        for(integer op_index=0;op_index<5;op_index++)
            for(integer signs=0;signs<4;signs++)
                for(integer a_shift=0;a_shift<4;a_shift++)
                    for(integer d_shift=0;d_shift<4;d_shift++)
                        for(integer tail=0;tail<4;tail++) begin
                            operation=operations[op_index];au=signs[0];bu=signs[1];du=(a_shift+d_shift)%2;
                            for(integer lane=0;lane<16;lane++) begin
                                aw[lane*16+:16]=au ? 16'((lane%4)*10923) : 16'(edges[lane%10]);
                                bw[lane*16+:16]=operation==11 ? 16'((lane%5)*8192) :
                                    bu ? 16'((lane%3)*16384) : 16'(edges[(lane+3)%10]);
                                cw[lane*16+:16]=16'(edges[(lane+5)%10]);
                            end
                            check_case(operation,aw,bw,cw,fractions[a_shift],fractions[(a_shift+1)%4],fractions[d_shift],tails[tail],au,bu,du,1);
                        end
        repeat(500) begin
            operation=operations[$urandom_range(0,4)];af=$urandom_range(0,24);bf=$urandom_range(0,24);df=$urandom_range(0,24);
            n=$urandom_range(1,16);au=$urandom_range(0,1);bu=$urandom_range(0,1);du=$urandom_range(0,1);
            for(integer lane=0;lane<16;lane++) begin
                aw[lane*16+:16]=au ? 16'($urandom_range(0,32768)) : 16'($urandom);
                bw[lane*16+:16]=(bu || operation==11) ? 16'($urandom_range(0,32768)) : 16'($urandom);
                cw[lane*16+:16]=16'($urandom);
            end
            check_case(operation,aw,bw,cw,af,bf,df,n,au,bu,du,1);
        end
        // U16 values outside the valid active tail are deliberately invalid.
        aw={16{16'hffff}};bw=aw;cw=0;
        for(integer lane=0;lane<3;lane++) begin aw[lane*16+:16]=16'(lane+1);bw[lane*16+:16]=16'(lane+2);end
        check_case(3,aw,bw,cw,0,0,0,3,1,1,0,1);
        check_case(1,aw,bw,cw,0,0,0,3,1,1,1,1);
        // An invalid recurrent gate stops after its own output, leaving the
        // remaining tail zero instead of consuming later elements.
        bw={16{16'h4000}};bw[16+:16]=16'h8001;
        check_case(11,{16{16'h1234}},bw,{16{16'hfedc}},15,15,15,4,0,0,0,1);
        for(integer bad=0;bad<4;bad++) begin
            aw={16{16'h0002}};bw={16{16'h0003}};
            if(bad[0]) aw[0+:16]=16'hffff;
            if(bad[1]) bw[16+:16]=16'hffff;
            check_case(3,aw,bw,0,0,0,0,5,1,1,0,1);
        end
        check_case(1,0,0,0,0,0,0,0,0,0,0,1);
        check_case(1,0,0,0,0,0,0,17,0,0,0,1);
        check_case(1,0,0,0,25,0,0,1,0,0,0,1);
        check_case(1,0,0,0,0,25,0,1,0,0,0,1);
        check_case(1,0,0,0,0,0,25,1,0,0,0,1);
        check_case(15,0,0,0,0,0,0,1,0,0,0,1);
        check_case(6,0,0,0,15,0,15,3,0,0,1,1);
        for(integer phase=1;phase<=6;phase++) reset_phase(phase);
        $display("ROWWISE_PASS cases=%0d elements=%0d busy_input_changes=%0d reset_phases=%0d reference=S128",checks,element_checks,busy_checks,reset_checks);
        $finish;
    end
    initial begin #10000000;$fatal(1,"ROWWISE_TIMEOUT");end
endmodule
