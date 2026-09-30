module fd_reg(
    input logic clk, rst_n, enable, flush,
    input logic [12:0] instr_fd,
    input logic [8:0] pc,
    output logic [12:0] instr_de,
    output logic [8:0] pc_de
);
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || flush) begin instr_de <= 0;pc_de <= 0;end
        else if (enable) begin instr_de <= instr_fd;pc_de <= pc;end
    end
endmodule
