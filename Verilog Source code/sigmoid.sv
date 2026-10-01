module sigmoid (
    input logic clk, rst_n, start,
    input logic signed [15:0] x_raw,
    input logic [4:0] frac_bits,
    output logic busy, done,
    output logic [15:0] y_raw
);
    import npu_pkg::*;
    // Generated together with sigmoid_257.mem; default ROM is independent of CWD.
`include "sigmoid_lut.svh"
    typedef enum logic [1:0] {IDLE, READ0, READ1, INTERP} state_t;
    state_t state;
    logic [8:0] index_q, index_next;
    logic [23:0] fraction_q, fraction_next;
    logic [15:0] y0, y1;
    logic signed [44:0] grid, x_extended;
    logic signed [63:0] interpolated;
    logic [9:0] difference;
    logic [33:0] product;

    logic [8:0] rom_address;
    logic [15:0] rom_data;

    // A single ROM lookup feeds both sample registers on successive cycles.
    // ASIC synthesis sees a constant case table, never an initialized RAM.
    assign rom_address = (state == READ1 && index_q != 9'h100) ?
    index_q + 9'h001 : index_q;
    assign rom_data = sigmoid_sample(int'(rom_address));
    always_comb begin
        // S16 at F_t=0..24 needs at most 45 signed coordinate bits,
        // including the 128-point offset. Keep all 24 fractional bits.
        x_extended = {{29{x_raw[15]}}, x_raw};
        grid = (x_extended <<< $unsigned(28 - int'(frac_bits))) + (45'sh000_0000_0080 <<< 24);
        if (grid <= 0) begin
            index_next = 0;
            fraction_next = 0;
        end
        else if (grid >= (45'sh000_0000_0100 <<< 24)) begin
            index_next = 9'h100;
            fraction_next = 0;
        end
        else begin
            index_next = grid[32:24];
            fraction_next = grid[23:0];
        end
        // Adjacent samples in the fixed LUT differ by at most 512.
        // Ten unsigned bits retain the exact slope, including the peak step.
        difference = 10'(y1 - y0);
        product = difference * fraction_q;
        // RNE applies to the entire result, including the integer parity of y0.
        interpolated = rne_shift64($signed({30'h0, product}) + (64'(y0) << 24), 6'd24);
    end
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            busy <= 0;
            done <= 0;
            y_raw <= 0;
            index_q <= 0;
            fraction_q <= 0;
            y0 <= 0;
            y1 <= 0;
        end else begin
            done <= 0;
            case (state)
                IDLE : if (start) begin
                    busy <= 1;
                    index_q <= index_next;
                    fraction_q <= fraction_next;
                    state <= READ0;
                end
                READ0 : begin
                    y0 <= rom_data;
                    state <= READ1;
                end
                READ1 : begin
                    y1 <= rom_data;
                    state <= INTERP;
                end
                INTERP : begin
                    y_raw <= interpolated[15:0];
                    busy <= 0;
                    done <= 1;
                    state <= IDLE;
                end
                default : state <= IDLE;
            endcase
        end
    end
endmodule
