module ins_mem #(
    parameter DEPTH=512,
    parameter ADDR_W=(DEPTH>1 ? $clog2(DEPTH) : 1),
    parameter INIT_FILE="instruction.mem"
) (
    input logic clk, 
    input logic [ADDR_W-1:0] addr,
    output logic [12:0] instr
);

    logic [12:0] mem [0:DEPTH-1];
    initial begin
        if (INIT_FILE != "") $readmemb(INIT_FILE, mem);
    end

    initial begin
        if (DEPTH < 1 || DEPTH > 2**ADDR_W) $fatal(1,"Invalid instruction depth/address width");
    end
    assign instr = mem[addr];

endmodule