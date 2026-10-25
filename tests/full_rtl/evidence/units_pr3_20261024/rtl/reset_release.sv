// Standard-cell reset boundary: immediate assertion, release after two clocks.
// No reset exception is needed: raw and internal reset paths remain timed.
module reset_release (
    input logic clk, rst_n,
    output logic core_rst_n
);
    logic release_first_q;
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) release_first_q <= 1'b0;
        else release_first_q <= 1'b1;

    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) core_rst_n <= 1'b0;
        else core_rst_n <= release_first_q;
endmodule
