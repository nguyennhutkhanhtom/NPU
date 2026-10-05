module PC(
    input logic clk,
    input logic rst_n,
    input logic clear,
    input logic advance,
    output logic [8:0] pc_out
);
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            pc_out <= 9'h000;
        else if (clear)
            pc_out <= 9'h000;
        else if (advance)
            pc_out <= pc_out + 9'h001;
    end
endmodule
