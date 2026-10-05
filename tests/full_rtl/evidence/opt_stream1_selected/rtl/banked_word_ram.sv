// Portable SRAM organization with bounded, reusable word-bank instances.
// Tiling keeps memory elaboration and address routing local as depth grows.
module sram_word_tile #(
    parameter int WIDTH = 32,
    parameter int ROWS = 1024
) (
    input logic clk, rd_en, wr_en,
    input logic [9:0] rd_addr, wr_addr,
    input logic [WIDTH - 1:0] wr_data,
    output logic [WIDTH - 1:0] rd_data
);
    logic [WIDTH - 1:0] memory [0:ROWS - 1];
    always_ff @(posedge clk) begin
        if (wr_en) memory[wr_addr] <= wr_data;
        if (rd_en) rd_data <= memory[rd_addr];
    end
endmodule

module banked_word_ram #(
    parameter int WIDTH = 32,
    parameter int ROWS = 4096,
    parameter int ADDR_W = $clog2(ROWS)
) (
    input logic clk, rd_en, wr_en,
    input logic [ADDR_W - 1:0] rd_addr, wr_addr,
    input logic [WIDTH - 1:0] wr_data,
    output logic [WIDTH - 1:0] rd_data
);
    localparam int TILES = (ROWS + 1023) / 1024;
    logic [WIDTH - 1:0] tile_data [0:TILES - 1];
    logic [TILES - 1:0] read_tile_q;
    genvar tile;
    generate
    for (tile = 0; tile < TILES; tile = tile + 1) begin : g_tile
        localparam int TILE_ROWS = (ROWS - tile * 1024 < 1024) ? ROWS - tile * 1024 : 1024;
        sram_word_tile #(.WIDTH(WIDTH), .ROWS(TILE_ROWS)) u_tile(
            .clk(clk), .rd_en(rd_en && (rd_addr >> 10) == tile),
            .wr_en(wr_en && (wr_addr >> 10) == tile),
            .rd_addr(10'(rd_addr)), .wr_addr(10'(wr_addr)),
            .wr_data(wr_data), .rd_data(tile_data[tile]));
        always_ff @(posedge clk)
            if (rd_en) read_tile_q[tile] <= (rd_addr >> 10) == tile;
    end
    endgenerate
    wire [WIDTH - 1:0] read_mux [0:TILES];
    genvar mux_tile;
    assign read_mux[0] = '0;
    generate
    for (mux_tile = 0; mux_tile < TILES; mux_tile = mux_tile + 1) begin : g_read_mux
        assign read_mux[mux_tile + 1] = read_mux[mux_tile] |
            (tile_data[mux_tile] & {WIDTH{read_tile_q[mux_tile]}});
    end
    endgenerate
    assign rd_data = read_mux[TILES];
endmodule
