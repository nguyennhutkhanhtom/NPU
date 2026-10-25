module mem_mapping (
    input logic clk,
    input logic rst_n,

    // Compute-side parameter SRAM port: 1024 x 256 = 32 KiB.
    input logic rd_en,
    input logic [9:0] rd_addr,
    output logic [255:0] rd_data,
    output logic rd_valid,
    input logic wr_en,
    input logic [9:0] wr_addr,
    input logic [255:0] wr_data,

    // 32-bit host port. host_addr is a 32-bit-word index (0..8191).
    input logic host_en,
    input logic host_we,
    input logic [12:0] host_addr,
    input logic [31:0] host_wdata,
    output logic [31:0] host_rdata,
    output logic host_rvalid
);
    // Shared implementation keeps host packing and read latency consistent.
    sram_256_wrapper #(.ADDR_W(10)) u_sram (
        .clk(clk),
        .rst_n(rst_n),
        .rd_en(rd_en),
        .rd_addr(rd_addr),
        .rd_data(rd_data),
        .rd_valid(rd_valid),
        .wr_en(wr_en),
        .wr_addr(wr_addr),
        .wr_data(wr_data),
        .host_en(host_en),
        .host_we(host_we),
        .host_addr(host_addr),
        .host_wdata(host_wdata),
        .host_rdata(host_rdata),
        .host_rvalid(host_rvalid)
    );
endmodule
