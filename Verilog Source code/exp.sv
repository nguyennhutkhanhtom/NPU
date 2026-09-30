module exp_row(
    input logic [15:0] a,
    output logic [15:0] result
);
    // EXP is not implemented in the ASIC baseline. Greedy decoding does not need softmax.
    // Drive zero so accidental legacy instantiation is deterministic.
    always_comb result = 16'h0000;
endmodule
