# banked_word_ram.sv — SRAM tiles và mux đọc

[Tài liệu](../../README.md) → [Source guide](../README.md) → [Mục lục](README.md)

**Source:** [banked_word_ram.sv](<../../../Verilog%20Source%20code/banked_word_ram.sv>). **Số dòng:** 50. **SHA-256:** `260bca8ecb29bb358e9633174f14bd5a012fa5fd2b986c461770b326a00e3799`.

## Khối này làm gì?

Một read port đồng bộ và một write port độc lập, old-data khi cùng địa chỉ. Mỗi tile tối đa 1024 word; read_tile_q giữ tag để mux output đúng tile. Nội dung và output không reset; client dùng valid riêng. ASIC macro hoặc Quartus IP có thể thay sram_word_tile sau cùng hợp đồng.

## Sơ đồ kiến trúc

```mermaid
flowchart TB
    REQ[Read and write requests] --> TILE[1024-word leaf SRAM]
    REQ --> TAG[Registered tile selection]
    TILE --> MUX[One-hot data reduction]
    TAG --> MUX
    MUX --> OUT[Read data after one edge]
```

## Cách hoạt động chi tiết

Một read port đồng bộ và một write port độc lập, old-data khi cùng địa chỉ. Mỗi tile tối đa 1024 word; read_tile_q giữ tag để mux output đúng tile. Nội dung và output không reset; client dùng valid riêng. ASIC macro hoặc Quartus IP có thể thay sram_word_tile sau cùng hợp đồng.

## Các nhóm logic trong source

### [Dòng 1–20: Leaf SRAM](<../../../Verilog%20Source%20code/banked_word_ram.sv#L1>)

<!-- source-range:1:20 -->
```systemverilog
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
```

Hai nonblocking assignment trả dữ liệu trước write khi read/write cùng địa chỉ. Không initialize hoặc reset memory.

### [Dòng 21–33: Bank organization](<../../../Verilog%20Source%20code/banked_word_ram.sv#L21>)

<!-- source-range:21:33 -->
```systemverilog
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
```

Chia ROWS thành tile; tile cuối có thể ngắn hơn. ADDR_W phải đủ cho ROWS và client chỉ phát địa chỉ hợp lệ.

### [Dòng 34–47: Tile decoding](<../../../Verilog%20Source%20code/banked_word_ram.sv#L34>)

<!-- source-range:34:47 -->
```systemverilog
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
    always_comb begin
        rd_data = '0;
        for (int tile_id = 0; tile_id < TILES; tile_id = tile_id + 1)
```

High address bits chọn tile, low 10 bits chọn word; tag đọc được chốt cùng cạnh với SRAM.

### [Dòng 48–50: Read output](<../../../Verilog%20Source%20code/banked_word_ram.sv#L48>)

<!-- source-range:48:50 -->
```systemverilog
            rd_data = rd_data | (tile_data[tile_id] & {WIDTH{read_tile_q[tile_id]}});
    end
endmodule
```

OR của các output được mask bằng tag one-hot. Latency logic là một cạnh; mux cuối vẫn phải đáp ứng STA.
