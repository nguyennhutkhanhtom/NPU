// Behavioral memory boundary for replacement by a foundry SRAM adapter.
// Compute reads retain the existing two-cycle request/response contract.
// Quartus uses synchronous host reads; other builds retain asynchronous reads.
module sram_256_wrapper #(
    parameter int ADDR_W = 8
) (
    input logic clk,
    input logic rst_n,
    input logic rd_en,
    input logic [ADDR_W - 1 : 0] rd_addr,
    output logic [255:0] rd_data,
    output logic rd_valid,
    input logic wr_en,
    input logic [ADDR_W - 1 : 0] wr_addr,
    input logic [255:0] wr_data,
    input logic host_en,
    input logic host_we,
    input logic [ADDR_W + 2 : 0] host_addr,
    input logic [31:0] host_wdata,
    output logic [31:0] host_rdata,
    output logic host_rvalid
);
    localparam int DEPTH = 1 << ADDR_W;
`ifndef QUARTUS_SYNTHESIS
    logic [255:0] memory [0 : DEPTH - 1];
    logic [ADDR_W - 1 : 0] read_address_q;
    logic read_pending_q;
`endif
    logic [ADDR_W - 1 : 0] write_address;
    logic [255:0] write_data;
    logic [7:0] write_mask;

`ifndef QUARTUS_SYNTHESIS
    assign host_rdata = memory[host_addr[ADDR_W + 2 : 3]][host_addr[2:0] * 32 +: 32];
    assign host_rvalid = host_en && !host_we;
`endif

    // One masked write port. Top-level arbitration makes the clients exclusive.
    always_comb begin
        write_address = wr_addr;
        write_data = wr_data;
        write_mask = {8{wr_en}};
        if (host_en && host_we) begin
            write_address = host_addr[ADDR_W + 2 : 3];
            write_data = {8{host_wdata}};
            write_mask = 8'b1 << host_addr[2:0];
        end
    end

`ifndef QUARTUS_SYNTHESIS
    // Memory data has no asynchronous reset, clear loop or initialization.
    always_ff @(posedge clk) begin
        if (rst_n) begin
            for (int lane = 0; lane < 8; lane ++ ) begin
                if (write_mask[lane]) begin
                    memory[write_address][lane * 32 +: 32] <= write_data[lane * 32 +: 32];
                end
            end
        end
    end
`endif

`ifdef QUARTUS_SYNTHESIS
    // Host accesses are mutually exclusive with compute accesses at the top
    // level.  Multiplex both clients onto one synchronous read port so Quartus
    // can infer simple dual-port block RAM instead of expanding the array into
    // registers and a very large asynchronous read mux.
    logic read_pending_q, read_host_q, response_host_q, read_valid_q;
    logic [ADDR_W - 1 : 0] shared_read_address_q;
    logic [ADDR_W - 1 : 0] response_address_q;
    logic [2:0] read_lane_q, response_lane_q;
    logic [255:0] read_row_q;

    assign rd_data = read_row_q;
    assign rd_valid = read_valid_q && !response_host_q;
    assign host_rdata = read_row_q[response_lane_q * 32 +: 32];
    // Both pipeline stages must belong to the current held request. A write
    // or idle cycle invalidates an earlier response, including the same address.
    assign host_rvalid = host_en && !host_we && read_valid_q && response_host_q &&
        read_pending_q && read_host_q &&
        {shared_read_address_q, read_lane_q} == host_addr &&
        {response_address_q, response_lane_q} == host_addr;

    // Eight independent 32-bit banks implement the lane mask with a write
    // enable per bank. Each bank has one whole-word write and synchronous read.
    // Neither the memory nor its output register has an asynchronous reset.
    genvar lane;
    generate
    for (lane = 0; lane < 8; lane = lane + 1) begin : g_ram_lane
        (* ramstyle = "M10K" *) logic [31:0] memory [0 : DEPTH - 1];
        always_ff @(posedge clk) begin
            if (rst_n && write_mask[lane])
                memory[write_address] <= write_data[lane * 32 +: 32];
            if (read_pending_q)
                read_row_q[lane * 32 +: 32] <= memory[shared_read_address_q];
        end
    end
    endgenerate

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            read_pending_q <= 1'b0;
            read_host_q <= 1'b0;
            response_host_q <= 1'b0;
            read_valid_q <= 1'b0;
            shared_read_address_q <= '0;
            response_address_q <= '0;
            read_lane_q <= '0;
            response_lane_q <= '0;
        end else begin
            read_valid_q <= read_pending_q;
            response_host_q <= read_host_q;
            response_lane_q <= read_lane_q;
            response_address_q <= shared_read_address_q;

            read_pending_q <= rd_en || (host_en && !host_we);
            if (host_en && !host_we) begin
                shared_read_address_q <= host_addr[ADDR_W + 2 : 3];
                read_host_q <= 1'b1;
                read_lane_q <= host_addr[2:0];
            end else if (rd_en) begin
                shared_read_address_q <= rd_addr;
                read_host_q <= 1'b0;
                read_lane_q <= '0;
            end
        end
    end
`else
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_valid <= 1'b0;
            read_pending_q <= 1'b0;
            read_address_q <= '0;
            rd_data <= '0;
        end else begin
            rd_valid <= read_pending_q;
            read_pending_q <= rd_en;
            if (rd_en) begin
                read_address_q <= rd_addr;
            end
            if (read_pending_q) begin
                rd_data <= memory[read_address_q];
            end
        end
    end
`endif

`ifndef SYNTHESIS
    always @(posedge clk) begin
        if (rst_n && host_en && (rd_en || wr_en || read_pending_q)) begin
            $error("Host and compute memory transactions must not overlap");
        end
    end
`endif
endmodule
