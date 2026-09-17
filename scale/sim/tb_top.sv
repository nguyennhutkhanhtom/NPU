`timescale 1ns/1ps
module tb_top;
    logic clk=0; always #5 clk=~clk;
    logic rst_n=0;
    wire ready,overflow,carry;
    wire [12:0] instr;
`ifdef SCALED
    wire [5:0] pc;
    wire [255:0] mem;
    matmulfree_scaled dut(.rst_n(rst_n),.clk(clk),.ready(ready),.overflow_out(overflow),.carry_out(carry),
                         .pc_debug(pc),.instr_debug(instr),.mem_out_1_debug(mem));
`else
    wire [8:0] pc;
    wire [511:0] mem;
    matmulfree dut(.rst_n(rst_n),.clk(clk),.ready(ready),.overflow_out(overflow),.carry_out(carry),
                  .pc_debug(pc),.instr_debug(instr),.mem_out_1_debug(mem));
`endif
    initial begin
        repeat(2) @(negedge clk);
        rst_n=1;
        repeat(12) @(negedge clk);
        if(ready!==1 || instr!==13'h1fff || pc!==0) $fatal(1,"HALT/reset regression failed");
        $display("TOP_SMOKE_PASS pc_width=%0d word_width=%0d ready=%b instr=%h",$bits(pc),$bits(mem),ready,instr);
        $finish;
    end
endmodule
