/*
 * RMSNorm unit for the project's 16-bit signed Q4.12 datapath.
 *
 * Paper-oriented implementation:
 *   Stage 1: latch the original 32-element vector and square every element
 *            with a lookup table.
 *   Stage 2: reduce the squared values with a balanced divide-and-conquer
 *            averaging tree and calculate RMS.
 *   Stage 3: divide every original element by the RMS.
 *
 * External format:
 *   x[i]   : signed Q4.12, 16 bits
 *   out[i] : signed Q4.12, 16 bits
 *
 * Square LUT:
 *   input  : signed Q4.6, x[i][15:6], 10 bits
 *   output : unsigned fixed point, 19 bits, 12 fractional bits
 *
 * IMPORTANT:
 *   normContent.mif must contain 1024 lines of 19-bit binary data generated
 *   by generate_norm_lut.py.
 */


/* -------------------------------------------------------------------------
 * Square ROM
 *
 * This has the same address-remapping idea as Sig_ROM:
 *   signed Q4.6 -> offset ROM address 0..1023
 *
 * The sign-bit flip is equivalent to the original +/- 512 remapping.
 * ------------------------------------------------------------------------- */
module Norm_Square_ROM #(
    parameter LUT_FILE = "data/normContent.mif"
) (
    input  logic        clk,
    input  logic        en,
    input  logic [15:0] x,       // signed Q4.12
    output logic [18:0] out      // unsigned, 12 fractional bits
);

    logic [18:0] mem [0:1023];

    logic signed [9:0] x_lut;    // signed Q4.6
    logic        [9:0] addr;

    // synthesis translate_off
    initial begin : check_lut
        integer fd;
        fd = $fopen(LUT_FILE, "r");
        if (fd == 0) $fatal(1, "Missing NORM square LUT: %s", LUT_FILE);
        else $fclose(fd);
    end
    // synthesis translate_on
    initial $readmemb(LUT_FILE, mem);

    // Q4.12 -> Q4.6.
    // This preserves sign + integer bits and the 6 MSB fractional bits.
    assign x_lut = $signed(x[15:6]);

    // Signed two's-complement ordering -> monotonically increasing ROM addr:
    // -8.0      ->   0
    //  0.0      -> 512
    // +7.984375 -> 1023
    always_ff @(posedge clk) begin
        if (en)
            addr <= {~x_lut[9], x_lut[8:0]};
    end

    assign out = mem[addr];

endmodule


/* -------------------------------------------------------------------------
 * 32-element RMSNorm
 *
 * Formula implemented:
 *
 *           x_i
 * y_i = --------------
 *        sqrt(mean(x^2))
 *
 * The fixed-point resolution is not sufficient to represent the tiny
 * epsilon used in floating-point software. A zero-RMS vector is therefore
 * handled explicitly and produces an all-zero output. This also applies to
 * nonzero samples in [0, 63] raw: all become zero after Q4.6 truncation.
 *
 * start is accepted only in IDLE.
 * done pulses for one cycle when out[] is updated.
 * ------------------------------------------------------------------------- */
module norm #(
    parameter LUT_FILE = "data/normContent.mif"
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        start,

    input  logic [15:0] x   [31:0],  // signed Q4.12
    output logic [15:0] out [31:0],  // signed Q4.12

    output logic        busy,
    output logic        done,
    output logic        overflow // OR of saturated lanes; valid with done
);

    typedef enum logic [1:0] {
        IDLE,
        RMS_STAGE,
        DIV_STAGE
    } state_t;

    state_t state;

    logic [15:0] x_buf [31:0];

    logic [18:0] square [31:0];
    logic          square_en;

    /*
     * Balanced reduction tree.
     *
     * Each square[] value has 12 fractional bits.
     *
     * Instead of right-shifting after every pairwise average (which would
     * repeatedly discard LSBs), the tree keeps the extra precision by
     * increasing the interpreted fractional-bit count by one at each level:
     *
     *   square : 19 bits, frac=12
     *   level1 : 20 bits, frac=13  -> mean of 2
     *   level2 : 21 bits, frac=14  -> mean of 4
     *   level3 : 22 bits, frac=15  -> mean of 8
     *   level4 : 23 bits, frac=16  -> mean of 16
     *   level5 : 24 bits, frac=17  -> mean of 32
     *
     * Numerically, level5 is the sum of the original raw square values,
     * but because its binary point has moved by 5 places it represents the
     * exact divide-by-32 mean without a large final divider and without
     * intermediate rounding loss.
     */
    logic [19:0] avg_l1 [15:0];
    logic [20:0] avg_l2 [7:0];
    logic [21:0] avg_l3 [3:0];
    logic [22:0] avg_l4 [1:0];
    logic [23:0] mean_sq_q17;

    logic [31:0] sqrt_radicand;
    logic [15:0] rms_comb;
    logic [15:0] rms_reg;        // unsigned RMS with 12 fractional bits

    genvar g;

    assign square_en = rst_n && (state == IDLE) && start;

    generate
        for (g = 0; g < 32; g = g + 1) begin : gen_square_rom
            Norm_Square_ROM #(.LUT_FILE(LUT_FILE)) square_rom (
                .clk (clk),
                .en  (square_en),
                .x   (x[g]),
                .out (square[g])
            );
        end
    endgenerate

    generate
        for (g = 0; g < 16; g = g + 1) begin : gen_avg_l1
            assign avg_l1[g] =
                {1'b0, square[2*g]} +
                {1'b0, square[2*g+1]};
        end

        for (g = 0; g < 8; g = g + 1) begin : gen_avg_l2
            assign avg_l2[g] =
                {1'b0, avg_l1[2*g]} +
                {1'b0, avg_l1[2*g+1]};
        end

        for (g = 0; g < 4; g = g + 1) begin : gen_avg_l3
            assign avg_l3[g] =
                {1'b0, avg_l2[2*g]} +
                {1'b0, avg_l2[2*g+1]};
        end

        for (g = 0; g < 2; g = g + 1) begin : gen_avg_l4
            assign avg_l4[g] =
                {1'b0, avg_l3[2*g]} +
                {1'b0, avg_l3[2*g+1]};
        end
    endgenerate

    assign mean_sq_q17 =
        {1'b0, avg_l4[0]} +
        {1'b0, avg_l4[1]};

    /*
     * mean_sq_q17 represents mean(x^2) with 17 fractional bits.
     *
     * We need RMS represented with 12 fractional bits:
     *
     *   rms_raw = sqrt(mean(x^2)) * 2^12
     *
     * Since:
     *   mean_sq_q17 = mean(x^2) * 2^17
     *
     * then:
     *   rms_raw^2 = mean_sq_q17 * 2^(24-17)
     *             = mean_sq_q17 << 7
     */
    assign sqrt_radicand = {1'b0, mean_sq_q17, 7'b0};

    /*
     * Unsigned integer square root.
     * Fixed 16-iteration restoring algorithm; synthesizable.
     */
    function automatic logic [15:0] isqrt_u32(input logic [31:0] value);
        logic [31:0] op;
        logic [31:0] res;
        logic [31:0] one;
        integer k;
        begin
            op  = value;
            res = 32'd0;

            // Highest power of four that fits in 32 bits: 2^30.
            one = 32'h4000_0000;

            for (k = 0; k < 16; k = k + 1) begin
                if (op >= (res + one)) begin
                    op  = op - (res + one);
                    res = (res >> 1) + one;
                end
                else begin
                    res = res >> 1;
                end

                one = one >> 2;
            end

            isqrt_u32 = res[15:0];
        end
    endfunction

    assign rms_comb = isqrt_u32(sqrt_radicand);

    /*
     * Q4.12 normalization:
     *
     * x_real   = x_raw   / 2^12
     * rms_real = rms_raw / 2^12
     *
     * y_raw = (x_real / rms_real) * 2^12
     *       = (x_raw << 12) / rms_raw
     */
    // Return {saturated, Q4.12 result}; division truncates toward zero.
    function automatic logic [16:0] normalize_q4_12(
        input logic [15:0] sample_bits,
        input logic [15:0] rms_raw
    );
        logic signed [31:0] sample_ext;
        logic signed [31:0] numerator;
        logic signed [31:0] quotient;
        logic signed [16:0] denominator;
        begin
            if (rms_raw == 16'd0) begin
                // Explicit zero-vector protection.
                normalize_q4_12 = 16'd0;
            end
            else begin
                sample_ext  = {{16{sample_bits[15]}}, sample_bits};
                numerator   = sample_ext <<< 12;
                denominator = $signed({1'b0, rms_raw});
                quotient    = numerator / denominator;

                // Saturate to signed Q4.12 range.
                if (quotient > 32'sd32767)
                    normalize_q4_12 = {1'b1, 16'h7FFF};
                else if (quotient < -32'sd32768)
                    normalize_q4_12 = {1'b1, 16'h8000};
                else
                    normalize_q4_12 = {1'b0, quotient[15:0]};
            end
        end
    endfunction

    assign busy = (state != IDLE);

    wire [16:0] normalized [31:0];
    wire [31:0] saturated;
    generate
        for (g = 0; g < 32; g = g + 1) begin : gen_normalize
            assign normalized[g] = normalize_q4_12(x_buf[g], rms_reg);
            assign saturated[g] = normalized[g][16];
        end
    endgenerate

    integer i;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state   <= IDLE;
            done    <= 1'b0;
            overflow <= 1'b0;
            rms_reg <= 16'd0;

            for (i = 0; i < 32; i = i + 1) begin
                x_buf[i] <= 16'd0;
                out[i]   <= 16'd0;
            end
        end
        else begin
            done <= 1'b0;

            case (state)
                IDLE: begin
                    if (start) begin
                        overflow <= 1'b0;
                        // Stage 1:
                        // Preserve the original full Q4.12 vector while the
                        // square ROMs register their Q4.6 addresses.
                        for (i = 0; i < 32; i = i + 1)
                            x_buf[i] <= x[i];

                        state <= RMS_STAGE;
                    end
                end

                RMS_STAGE: begin
                    // Stage 2:
                    // square[] is now valid. The balanced tree computes the
                    // mean-square and this register captures sqrt(mean-square).
                    rms_reg <= rms_comb;
                    state   <= DIV_STAGE;
                end

                DIV_STAGE: begin
                    // Stage 3:
                    // Normalize the original Q4.12 samples.
                    for (i = 0; i < 32; i = i + 1)
                        out[i] <= normalized[i][15:0];

                    overflow <= |saturated;
                    done  <= 1'b1;
                    state <= IDLE;
                end

                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule
