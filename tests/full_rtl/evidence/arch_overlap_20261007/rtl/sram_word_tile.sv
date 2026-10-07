module sram_word_tile #(
    parameter int WIDTH = 32,
    parameter int ROWS = 1024
) (
    input logic clk, rd_en, wr_en,
    input logic [9:0] rd_addr, wr_addr,
    input logic [WIDTH - 1:0] wr_data,
    output logic [WIDTH - 1:0] rd_data
);
    logic [WIDTH - 1:0] memory [0:ROWS - 1];
    always_ff @(posedge clk) begin
        if (wr_en) memory[wr_addr] <= wr_data;
        if (rd_en) rd_data <= memory[rd_addr];
    end
endmodule
