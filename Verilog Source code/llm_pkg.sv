package llm_pkg;
    // Fixed NanoFable graph: four blocks, 128 channels, four 32-channel heads.
    localparam int CONTEXT = 128;
    localparam int PARAM_ROWS = 24576;
    localparam int EMB_SCALE_BASE = 23040;
    localparam int MATRIX_META_BASE = 23552;
    localparam int GAIN_BASE = 23580;
    localparam int ROPE_BASE = 23652;

    function automatic logic signed [23:0] llm_sat24(input logic signed [63:0] x);
        if (x > 64'sd8388607) llm_sat24 = 24'sh7fffff;
        else if (x < -64'sd8388608) llm_sat24 = 24'sh800000;
        else llm_sat24 = x[23:0];
    endfunction

    function automatic logic signed [63:0] llm_extend56(input logic signed [55:0] x);
        llm_extend56 = {{8{x[55]}}, x};
    endfunction

    `include "llm_exp_lut.svh"
    `include "llm_gumbel_lut.svh"
    function automatic logic [31:0] llm_random_next(input logic [31:0] previous);
        logic [31:0] x;
        begin
            x = previous ^ (previous << 13);
            x = x ^ (x >> 17);
            llm_random_next = x ^ (x << 5);
        end
    endfunction
endpackage
