module ins_mem(
    input logic clk,
    input logic [8:0] addr,
    output logic [12:0] instr,
    input logic host_we,
    input logic [8:0] host_addr,
    input logic [12:0] host_instr,
    output logic [12:0] host_rinstr
);
    logic [12:0] mem [0:511];
    assign instr = mem[addr];
    assign host_rinstr = mem[host_addr];
    always_ff @(posedge clk) begin
        if (host_we)
            mem[host_addr] <= host_instr;
    end
endmodule
