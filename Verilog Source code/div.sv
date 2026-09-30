// Small sequential unsigned divider used by the scalar unit.
// Signed operations are formed outside this block from magnitudes/signs.
module div #(
    parameter int NUM_W = 64,
    parameter int DEN_W = 32
) (
    input logic clk,
    input logic rst_n,
    input logic start,
    input logic [NUM_W - 1 : 0] numerator,
    input logic [DEN_W - 1 : 0] denominator,
    output logic busy,
    output logic done,
    output logic div_zero,
    output logic [NUM_W - 1 : 0] quotient,
    output logic [DEN_W - 1 : 0] remainder
);
    localparam int CW = $clog2(NUM_W + 1);
    logic [NUM_W - 1 : 0] q_work;
    logic [DEN_W : 0] rem_work;
    logic [DEN_W - 1 : 0] den_reg;
    logic [CW - 1 : 0] count;
    logic [DEN_W : 0] rem_shift;
    logic [NUM_W - 1 : 0] q_next;

    always_comb begin
        rem_shift = {rem_work[DEN_W - 1 : 0], q_work[NUM_W - 1]};
        q_next = {q_work[NUM_W - 2 : 0], 1'b0};
        if (rem_shift >= {1'b0, den_reg}) begin
            rem_shift = rem_shift - {1'b0, den_reg};
            q_next[0] = 1'b1;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy <= 1'b0; done <= 1'b0; div_zero <= 1'b0;
            quotient <= '0; remainder <= '0; q_work <= '0;
            rem_work <= '0; den_reg <= '0; count <= '0;
        end else begin
            done <= 1'b0;
            if (start && !busy) begin
                div_zero <= (denominator == 0);
                if (denominator == 0) begin
                    quotient <= '1;
                    remainder <= numerator[DEN_W - 1 : 0];
                    done <= 1'b1;
                end else begin
                    busy <= 1'b1;
                    q_work <= numerator;
                    rem_work <= '0;
                    den_reg <= denominator;
                    count <= CW'(NUM_W);
                end
            end else if (busy) begin
                q_work <= q_next;
                rem_work <= rem_shift;
                count <= count - 1'b1;
                if (count == 1) begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    quotient <= q_next;
                    remainder <= rem_shift[DEN_W - 1 : 0];
                end
            end
        end
    end
endmodule
