module sigmoid #(parameter string LUT_FILE = "") (
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
    logic signed [63:0] grid, x_extended, interpolated;
    logic [15:0] difference;
    logic [39:0] product;

    logic [8:0] rom_address;
    logic [15:0] rom_data;

    // A single ROM lookup feeds both sample registers on successive cycles.
    // ASIC synthesis sees a constant case table, never an initialized RAM.
    assign rom_address = (state == READ1 && index_q != 9'h100) ?
    index_q + 9'h001 : index_q;
`ifdef SYNTHESIS
    assign rom_data = sigmoid_sample(int'(rom_address));
`else
    generate
        if (LUT_FILE == "") begin : g_builtin_rom
            assign rom_data = sigmoid_sample(int'(rom_address));
        end else begin : g_file_rom
            logic [15:0] lut [0:256];
            initial begin
                begin : validate_file
                    integer fd, rc, value, count;
                    fd = $fopen(LUT_FILE, "r");
                    if (fd == 0) $fatal(1, "Missing sigmoid LUT: %s", LUT_FILE);
                    count = 0;
                    while (!$feof(fd)) begin
                        rc = $fscanf(fd, "%h", value);
                        if (rc == 1) begin
                            if (count >= 257) $fatal(1, "Extra sigmoid LUT entries");
                            if (value !== {16'h0000, sigmoid_sample(count)})
                                $fatal(1, "Incorrect sigmoid LUT sample %0d", count);
                            count = count + 1;
                        end else if (!$feof(fd)) $fatal(1, "Malformed sigmoid LUT");
                    end
                    $fclose(fd);
                    if (count != 257) $fatal(1, "Sigmoid LUT requires exactly 257 samples");
                end
                $readmemh(LUT_FILE, lut);
            end
            assign rom_data = lut[rom_address];
        end
    endgenerate
`endif
    always_comb begin
        // All S16 inputs at F_t=0..24 have exact coordinates with 24 fraction bits.
        x_extended = {{48{x_raw[15]}}, x_raw};
        grid = (x_extended <<< $unsigned(28 - int'(frac_bits))) + (64'sh0000_0000_0000_0080 <<< 24);
        if (grid <= 0) begin
            index_next = 0;
            fraction_next = 0;
        end
        else if (grid >= (64'sh0000_0000_0000_0100 <<< 24)) begin
            index_next = 9'h100;
            fraction_next = 0;
        end
        else begin
            index_next = grid[32:24];
            fraction_next = grid[23:0];
        end
        difference = y1 - y0;
        product = difference * fraction_q;
        // RNE applies to the entire result, including the integer parity of y0.
        interpolated = rne_shift64($signed({24'h00_0000, product}) + (64'(y0) << 24), 6'd24);
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
