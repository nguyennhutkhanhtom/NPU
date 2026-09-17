module PC(
    input wire clk,
    input wire rst,
    input wire stall,
    output reg [8:0] pc_out
);

    // Internal wires
    logic [8:0] pc_next;

    // Program Counter
    always_ff @(posedge clk or negedge rst) begin
        if (!rst)
            pc_out <= 9'h00;
        else if(stall)
            pc_out <= pc_next;
    end

    // Next Program Counter
    always_comb begin
        pc_next = pc_out + 9'h01;
    end

endmodule
