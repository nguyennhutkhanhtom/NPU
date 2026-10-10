// Generic synchronous memory boundary for replacement by a foundry SRAM adapter.
// Host and compute reads share the same two-cycle request/response contract.
module sram_256_wrapper #(
    parameter int ADDR_W = 8,
    parameter int DEPTH = 1 << ADDR_W
) (
    input logic clk,
    input logic rst_n,
    // Compute port: rd_en requests one full 256-bit row. rd_data must only be
    // consumed when rd_valid is asserted. wr_en writes all eight 32-bit banks.
    input logic rd_en,
    input logic [ADDR_W - 1 : 0] rd_addr,
    output logic [255:0] rd_data,
    output logic rd_valid,
    input logic wr_en,
    input logic [ADDR_W - 1 : 0] wr_addr,
    input logic [255:0] wr_data,
    // Host port: host_en marks a request and host_we selects write (1) or read
    // (0). host_addr counts 32-bit lanes, so its low three bits select one of
    // eight lanes and the remaining bits select the 256-bit row.
    input logic host_en,
    input logic host_we,
    input logic [ADDR_W + 2 : 0] host_addr,
    input logic [31:0] host_wdata,
    output logic [31:0] host_rdata,
    output logic host_rvalid
);
    logic [ADDR_W - 1 : 0] write_address;
    logic [255:0] write_data;
    logic [7:0] write_mask;


    // This combinational block synthesizes a write-data/address mux plus eight
    // lane enables. Defaults select the compute client. Assigning every output
    // before the if covers all input cases, so no state/latch is inferred.
    // Top-level arbitration makes the clients exclusive; the host branch has
    // priority only to keep the mux deterministic if that contract is violated.
    always_comb begin
        write_address = wr_addr;
        write_data = wr_data;
        // Compute writes are whole-row writes: wr_en=1 enables all eight banks.
        write_mask = {8{wr_en}};
        if (host_en && host_we) begin
            // Remove three lane bits to obtain the row address. Replicate the
            // 32-bit payload to all banks, then enable only the selected bank.
            write_address = host_addr[ADDR_W + 2 : 3];
            write_data = {8{host_wdata}};
            write_mask = 8'b1 << host_addr[2:0];
        end
    end


    // Top-level arbitration makes host and compute accesses exclusive.
    // One synchronous read port serves both clients with tagged responses.
    logic read_pending_q, read_host_q, response_host_q, read_valid_q;
    logic [ADDR_W - 1 : 0] shared_read_address_q;
    logic [ADDR_W - 1 : 0] response_address_q;
    logic [2:0] read_lane_q, response_lane_q;
    logic [255:0] read_row_q;

    assign rd_data = read_row_q;
    assign rd_valid = read_valid_q && !response_host_q;
    assign host_rdata = read_row_q[(int'(response_lane_q) << 5) +: 32];
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
        banked_word_ram #(.WIDTH(32), .ROWS(DEPTH), .ADDR_W(ADDR_W)) u_storage(
            .clk(clk), .rd_en(read_pending_q), .wr_en(rst_n && write_mask[lane]),
            .rd_addr(shared_read_address_q), .wr_addr(write_address),
            .wr_data(write_data[lane * 32 +: 32]), .rd_data(read_row_q[lane * 32 +: 32]));
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

endmodule
