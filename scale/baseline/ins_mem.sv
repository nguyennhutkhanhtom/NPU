module ins_mem(
    input logic clk, 
    input logic [8:0] addr,
    output logic [12:0] instr
);

    logic [12:0] mem [0:511];
    initial begin
        $readmemb("instruction.mem", mem);
    end

    assign instr = mem[addr];

endmodule