module fd_reg #(parameter WORD_W=512, PC_W=9) (
    input logic clk, rst_n,
    input logic [12:0] instr_fd,
    input logic [PC_W-1:0] pc,
    input logic enable,
    output logic [12:0] instr_de,
    output logic [PC_W-1:0] pc_de
);

        always_ff @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                instr_de <= 13'b0;
                pc_de <= '0;
            end
            else if (enable) begin
                instr_de <= instr_fd;
                pc_de <= pc;
            end
        end

endmodule
