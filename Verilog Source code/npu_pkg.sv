package npu_pkg;
    parameter int SRAM_W = 256;
    parameter int PARAM_AW = 10;
    parameter int WORK_AW = 8;
    parameter int PARAM_DEPTH = 1 << PARAM_AW; // 1024 words = 32 KiB
    parameter int WORK_DEPTH = 1 << WORK_AW; // 256 words = 8 KiB

    parameter int ACT_W = 8;
    parameter int STATE_W = 16;
    parameter int WEIGHT_W = 2;
    parameter int DOT_LANES = 32;
    parameter int VEC_LANES = 2;
    parameter int ACC_W = 18;
    parameter int K_MAX = 512;

    parameter int M_W = 24;
    parameter int SHIFT_W = 6;

    typedef enum logic [1:0] {
    FMT_S8 = 2'h0,
    FMT_S16 = 2'h1,
    FMT_U16 = 2'h2,
    FMT_S32 = 2'h3
    } tensor_fmt_t;

    // Workspace descriptor. length counts logical elements, not SRAM words.
    typedef struct packed {
    logic [7:0] base_word;
    logic [9:0] length;
    tensor_fmt_t fmt;
    logic [4:0] frac_bits;
    logic [6:0] reserved;
    } ws_desc_t; // 32 bits

    // Ternary matrix descriptor. Each output row begins on a 256-bit word boundary.
    // Weight rows use ceil(K/128) words. Biases are S32, 8 values/word.
    typedef struct packed {
    logic [9:0] weight_base;
    logic [9:0] bias_base;
    logic [9:0] k_len;
    logic [9:0] n_rows;
    logic [23:0] scale_m;
    logic [5:0] scale_r;
    logic output_s32; // 0: saturate to S16, 1: saturate to S32
    logic [24:0] reserved; // bit0: dynamic q scale; bit1: no bias
    } mat_desc_t; // 96 bits

    function automatic logic signed [15:0] sat_s16(input logic signed [63:0] x);
        if (x > 64'sh0000_0000_0000_7fff) sat_s16 = 16'sh7fff;
        else if (x < - 64'sh0000_0000_0000_8000) sat_s16 = 16'sh8000;
        else sat_s16 = x[15:0];
    endfunction

    function automatic logic signed [31:0] sat_s32(input logic signed [63:0] x);
        if (x > 64'sh0000_0000_7fff_ffff) sat_s32 = 32'sh7fff_ffff;
        else if (x < - 64'sh0000_0000_8000_0000) sat_s32 = 32'sh8000_0000;
        else sat_s32 = x[31:0];
    endfunction

    // Round-to-nearest-even signed arithmetic right shift, including shift=0.
    // Arithmetic shift gives floor(x/2^shift); discarded bits encode its remainder.
    function automatic logic signed [63:0] rne_shift64(
            input logic signed [63:0] x,
            input logic [5:0] shift
        );
        logic signed [63:0] q;
        logic [63:0] discarded;
        logic guard;
        logic sticky;
        logic inc;
        begin
            // A 7-bit shift amount represents 64: shift=0 discards no bits.
            // This avoids magnitude/sign negators and a variable subtract-one mask.
            q = x >>> shift;
            discarded = $unsigned(x) << (7'd64 - {1'b0, shift});
            guard = discarded[63];
            sticky = |discarded[62:0];
            inc = guard && (sticky || q[0]);
            rne_shift64 = q + $signed({63'h0, inc});
        end
    endfunction

    // RNE for the signed 42-bit postscale product. At shift >= 42 every
    // S42 value rounds to zero, including the minimum value's even tie.
    function automatic logic signed [41:0] rne_shift42(
            input logic signed [41:0] x,
            input logic [5:0] shift
        );
        logic signed [41:0] q;
        logic [41:0] discarded;
        logic inc;
        begin
            q = x >>> shift;
            discarded = $unsigned(x) << (7'd42 - {1'b0, shift});
            inc = discarded[41] && ((|discarded[40:0]) || q[0]);
            if (shift >= 42) rne_shift42 = '0;
            else rne_shift42 = q + $signed({41'h0, inc});
        end
    endfunction

    // Shift is positive for division, negative for multiplication by a power of two.
    // Callers constrain left shifts to <=24 and operands to at most 33 signed bits.
    function automatic logic signed [63:0] scale_shift64(
            input logic signed [63:0] x, input integer shift
        );
        if (shift >= 0) scale_shift64 = rne_shift64(x, shift[5:0]);
        else scale_shift64 = x <<< $unsigned( - shift);
    endfunction

    function automatic integer ws_words(input ws_desc_t d);
        case (d.fmt)
            FMT_S8 : ws_words = ((int'(d.length) + 31) >> 5);
            FMT_S16, FMT_U16 : ws_words = ((int'(d.length) + 15) >> 4);
            default : ws_words = ((int'(d.length) + 7) >> 3);
        endcase
    endfunction

    function automatic logic ws_valid(input ws_desc_t d);
        ws_valid = d.length > 0 && d.length <= K_MAX && d.frac_bits <= 24 &&
        int'(d.base_word) + ws_words(d) <= WORK_DEPTH;
    endfunction

    function automatic logic ranges_overlap(input integer a, input integer an,
            input integer b, input integer bn);
        ranges_overlap = a < b + bn && b < a + an;
    endfunction

endpackage
