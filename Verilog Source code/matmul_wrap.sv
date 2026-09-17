module matmul_wrap(
    input logic CLOCK_50,
    input logic [0:0] SW,
    output logic [2:0] LEDG
);

    matmulfree matmulfree_inst (
        .clk(CLOCK_50),
        .rst_n(SW[0]),
        .ready(LEDG[0]),
        .overflow_out(LEDG[1]),
        .carry_out(LEDG[2])
    );

endmodule