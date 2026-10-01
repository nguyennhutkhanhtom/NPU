// Compose postscale from the runtime NORM+QUANT scale:
// C = factor_m * quant_d / (127*65536 * 2^factor_r).
// Find the largest r<=47 whose RNE coefficient fits U24. No floating point.
module scale_compose (
    input logic clk, rst_n, start,
    input logic [23:0] factor_m, quant_d,
    input logic [5:0] factor_r,
    output logic busy, done, format_error,
    output logic [23:0] result_m,
    output logic [5:0] result_r
);
    typedef enum logic [2:0] {IDLE, PREP, DIV_START, DIV_WAIT, FINISH} state_t;
    state_t state;
    logic [47:0] numerator_base;
    logic [5:0] base_r, candidate;
    logic [47:0] numerator;
    logic [24:0] denominator;
    logic [47:0] quotient;
    logic [24:0] remainder;
    logic div_busy, div_done, div_zero;
    logic [48:0] rounded;
    logic [25:0] twice_rem;
    logic round_up;
    integer shift;
    logic shift_overflow;
    logic coefficient_fits;
    // U24 max is odd: the half-way value rounds up to 2^24, which is invalid.
    // RNE(n/d) fits iff n < (2^24 - 1/2)*d. For d=127*65536 this is U47.
    localparam logic [46:0] COEFFICIENT_LIMIT = 47'h7eff_ffc0_8000;
    always_comb begin
        shift = int'(candidate) - int'(base_r);
        numerator = numerator_base;
        denominator = 25'h07f_0000;
        shift_overflow = 0;
        if (shift >= 0) begin
            shift_overflow = numerator > (48'hffff_ffff_ffff >> $unsigned(shift));
            numerator = numerator << $unsigned(shift);
        end else begin
            shift_overflow = denominator > (25'h1ff_ffff >> $unsigned( - shift));
            denominator = denominator << $unsigned( - shift);
        end
        // Reject overlarge coefficients before spending 48 divider cycles.
        // For shift <= -2, even the largest U24*U24 product is below 4*limit.
        coefficient_fits = 1'b1;
        if (shift >= 0) coefficient_fits = numerator < {1'b0, COEFFICIENT_LIMIT};
        else if (shift == -1) coefficient_fits = numerator_base < {COEFFICIENT_LIMIT, 1'b0};
        twice_rem = {1'b0, remainder} << 1;
        round_up = (twice_rem > {1'b0, denominator}) ||
            ((twice_rem == {1'b0, denominator}) && quotient[0]);
        rounded = {1'b0, quotient} + {48'h0000_0000_0000, round_up};
    end
    // Every launch has shift >= -2. A fitting positive shift gives n < limit;
    // a negative shift leaves the U48 product unchanged and d <= 127*65536*4.
    div #(.NUM_W(48),
        .DEN_W(25)) u_div(
        .clk(clk),
        .rst_n(rst_n),
        .start(state == DIV_START),
        .numerator(numerator),
        .denominator(denominator),
        .busy(div_busy),
        .done(div_done),
        .div_zero(div_zero),
        .quotient(quotient),
        .remainder(remainder));
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            busy <= 0;
            done <= 0;
            format_error <= 0;
            numerator_base <= 0;
            base_r <= 0;
            candidate <= 0;
            result_m <= 0;
            result_r <= 0;
        end else begin
            done <= 0;
            case (state)
                IDLE : if (start) begin
                    busy <= 1;
                    format_error <= 0;
                    result_m <= 0;
                    result_r <= 0;
                    numerator_base <= factor_m * quant_d;
                    base_r <= factor_r;
                    candidate <= 47;
                    if (factor_r > 47 || quant_d == 0) begin
                        format_error <= 1;
                        state <= FINISH;
                    end
                    else if (factor_m == 0) state <= FINISH;
                    else state <= PREP;
                end
                PREP : begin
                    // Starting shift is nonnegative, and shift=-2 always fits.
                    // Guard the narrowed divider interface if that invariant is violated.
                    if (shift < -2) begin
                        format_error <= 1;
                        state <= FINISH;
                    end else if (shift_overflow) begin
                        if (shift < 0 || candidate == 0) begin
                            format_error <= 1;
                            state <= FINISH;
                        end
                        else candidate <= candidate - 1'b1;
                    end else if (!coefficient_fits) begin
                        if (candidate == 0) begin
                            format_error <= 1;
                            state <= FINISH;
                        end else candidate <= candidate - 1'b1;
                    end else state <= DIV_START;
                end
                DIV_START : state <= DIV_WAIT;
                DIV_WAIT : if (div_done) begin
                    if (div_zero || rounded == 0) begin
                        format_error <= 1;
                        state <= FINISH;
                    end
                    else if (rounded > 49'h00ff_ffff) begin
                        if (candidate == 0) begin
                            format_error <= 1;
                            state <= FINISH;
                        end
                        else begin
                            candidate <= candidate - 1'b1;
                            state <= PREP;
                        end
                    end else begin
                        result_m <= rounded[23:0];
                        result_r <= candidate;
                        state <= FINISH;
                    end
                end
                FINISH : begin
                    busy <= 0;
                    done <= 1;
                    state <= IDLE;
                end
                default : state <= IDLE;
            endcase
        end
    end
endmodule
