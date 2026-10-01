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
    initial begin
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
        $fclose(fd);$display("HOST_PASS cases=%0d",cases_run);$finish;
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
        $display("SIGMOID_PASS cases=%0d formats=25 protocol_checks=2",index);$finish;
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
