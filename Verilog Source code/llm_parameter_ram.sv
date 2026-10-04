// Parameter SRAM boundary. Compute reads: four edges for <=4096 rows, otherwise
// five; host lane selection adds one edge, followed by the controller response.
// Writes acknowledge after leaf commit.
// Contents/payloads are unreset; reset cancels all queued requests and validity.
module llm_parameter_ram #(
    parameter int ADDR_W = 15,
    parameter int DEPTH = 24576,
    parameter bit USE_QUARTUS_MEMORY = 0
) (
    input logic clk, rst_n, rd_en,
    input logic [ADDR_W - 1:0] rd_addr,
    output logic [255:0] rd_data,
    output logic rd_valid,
    input logic host_active, host_we, host_read_req, host_write_req,
    input logic [ADDR_W + 2:0] host_addr,
    input logic [31:0] host_wdata,
    output logic [31:0] host_rdata,
    output logic host_rvalid
);
    localparam int READ_LATENCY = DEPTH <= 4096 ? 4 : 5;
    localparam int LAST_READ = READ_LATENCY - 1;
    logic [READ_LATENCY - 1:0] read_valid_q, read_host_q;
    logic [ADDR_W + 2:0] read_address_q [0:LAST_READ];
    logic [7:0] lane_read_valid, lane_write_valid;
    logic [255:0] read_row;
    logic host_read_valid_q, host_write_valid_q;
    logic [ADDR_W + 2:0] response_address_q;
    wire read_request = rd_en || host_read_req;
    // Host and compute reads are mutually exclusive under top arbitration.
    // The registered compute owner selects payload; raw host cancellation
    // affects validity/enables without driving the wide address mux.
    wire [ADDR_W - 1:0] read_address = rd_en ? rd_addr : host_addr[ADDR_W + 2:3];
    assign rd_data = read_row;
    assign rd_valid = read_valid_q[LAST_READ] && !read_host_q[LAST_READ];
    assign host_rvalid = host_active && (host_we ? host_write_valid_q :
        host_read_valid_q && response_address_q == host_addr);
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            read_valid_q <= 0; read_host_q <= 0;
            host_read_valid_q <= 0; host_write_valid_q <= 0;
        end else begin
            read_valid_q[0] <= read_request;
            read_host_q[0] <= host_read_req;
            for (int stage = 1; stage < READ_LATENCY; stage = stage + 1) begin
                read_valid_q[stage] <= read_valid_q[stage - 1] &&
                    (!read_host_q[stage - 1] ||
                        (host_active && !host_we && host_addr == read_address_q[stage - 1]));
                read_host_q[stage] <= read_host_q[stage - 1];
            end
            host_read_valid_q <= read_valid_q[LAST_READ] && read_host_q[LAST_READ] &&
                host_active && !host_we && host_addr == read_address_q[LAST_READ];
            host_write_valid_q <= (|lane_write_valid) && host_active && host_we;
        end
    end
    always_ff @(posedge clk) begin
        read_address_q[0] <= host_addr;
        for (int stage = 1; stage < READ_LATENCY; stage = stage + 1)
            read_address_q[stage] <= read_address_q[stage - 1];
        if (read_valid_q[LAST_READ] && read_host_q[LAST_READ]) begin
            response_address_q <= read_address_q[LAST_READ];
            host_rdata <= read_row[(int'(read_address_q[LAST_READ][2:0]) << 5) +: 32];
        end
    end
    genvar lane;
    generate
    for (lane = 0; lane < 8; lane = lane + 1) begin : g_ram_lane
        (* dont_merge *) logic [ADDR_W - 1:0] read_address_local_q, write_address_q;
        (* dont_merge *) logic [31:0] write_data_q;
        logic read_enable_q, write_enable_q;
        always_ff @(posedge clk) begin
            read_address_local_q <= read_address;
            write_address_q <= host_addr[ADDR_W + 2:3];
            write_data_q <= host_wdata;
        end
        always_ff @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin read_enable_q <= 0; write_enable_q <= 0; end
            else begin
                read_enable_q <= read_request;
                write_enable_q <= host_write_req && host_addr[2:0] == 3'(lane);
            end
        end
        pipelined_word_ram #(.WIDTH(32), .ROWS(DEPTH), .ADDR_W(ADDR_W),
            .USE_QUARTUS_MEMORY(USE_QUARTUS_MEMORY)) u_storage(
            .clk(clk), .rst_n(rst_n), .rd_en(read_enable_q), .wr_en(write_enable_q),
            .rd_addr(read_address_local_q), .wr_addr(write_address_q), .wr_data(write_data_q),
            .rd_data(read_row[lane * 32 +: 32]), .rd_valid(lane_read_valid[lane]),
            .wr_valid(lane_write_valid[lane]));
    end
    endgenerate
endmodule
