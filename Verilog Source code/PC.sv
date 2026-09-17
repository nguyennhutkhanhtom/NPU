module PC #(parameter PC_W=9) (
    input wire clk,
    input wire rst,
    input wire stall,
    output reg [PC_W-1:0] pc_out
);

    // Internal wires
    logic [PC_W-1:0] pc_next;

    // Program Counter
    always_ff @(posedge clk or negedge rst) begin
        if (!rst)
            pc_out <= '0;
        else if(stall)
            pc_out <= pc_next;
    end

    // Next Program Counter
    always_comb begin
        pc_next = pc_out + PC_W'(1);
    end

endmodule
