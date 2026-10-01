module ins_mem (
    input logic clk,
    input logic rst_n,
    input logic fetch_en,
    input logic [8:0] addr,
    output logic [12:0] instr,
    output logic instr_valid,
    input logic host_en,
    input logic host_we,
    input logic [8:0] host_addr,
    input logic [12:0] host_instr,
    output logic [12:0] host_rinstr,
    output logic host_rvalid
);

    logic [12:0] mem [0:511];
    logic [12:0] read_data_q;
    logic [8:0] read_address_q, response_address_q;
    logic read_pending_q, read_host_q, response_host_q, read_valid_q;

    // Host and fetch share one synchronous read port. Neither RAM nor its
    // output register has an asynchronous reset or initialization loop.
    always_ff @(posedge clk) begin
        if (rst_n && host_en && host_we)
            mem[host_addr] <= host_instr;
        if (read_pending_q)
            read_data_q <= mem[read_address_q];
    end

    assign instr = read_data_q;
    assign host_rinstr = read_data_q;
    assign instr_valid = fetch_en && read_valid_q && !response_host_q &&
        read_pending_q && !read_host_q &&
        read_address_q == addr && response_address_q == addr;
    assign host_rvalid = host_en && !host_we && read_valid_q && response_host_q &&
        read_pending_q && read_host_q &&
        read_address_q == host_addr && response_address_q == host_addr;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            read_address_q <= '0;
            response_address_q <= '0;
            read_pending_q <= 1'b0;
            read_host_q <= 1'b0;
            response_host_q <= 1'b0;
            read_valid_q <= 1'b0;
        end else begin
            read_valid_q <= read_pending_q;
            response_host_q <= read_host_q;
            response_address_q <= read_address_q;
            read_pending_q <= fetch_en || (host_en && !host_we);
            if (host_en && !host_we) begin
                read_address_q <= host_addr;
                read_host_q <= 1'b1;
            end else if (fetch_en) begin
                read_address_q <= addr;
                read_host_q <= 1'b0;
            end
        end
    end
endmodule
