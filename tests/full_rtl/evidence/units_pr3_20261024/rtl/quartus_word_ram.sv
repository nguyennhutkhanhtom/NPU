// FPGA memory technology binding only. ASIC integration replaces this module
// behind pipelined_word_ram; compute/control contain no Quartus IP instances.
// One synchronous read and one write, common clock, one-edge raw read latency.
// Mixed-port same-address collision returns OLD_DATA. No storage/output reset.
module quartus_word_ram #(
    parameter int WIDTH = 32,
    parameter int ROWS = 4096,
    parameter int ADDR_W = $clog2(ROWS)
) (
    input logic clk, rd_en, wr_en,
    input logic [ADDR_W - 1:0] rd_addr, wr_addr,
    input logic [WIDTH - 1:0] wr_data,
    output wire [WIDTH - 1:0] rd_data
);
    altsyncram #(
        .intended_device_family("Cyclone V"),
        .operation_mode("DUAL_PORT"), .ram_block_type("M10K"),
        .width_a(WIDTH), .width_b(WIDTH),
        .widthad_a(ADDR_W), .widthad_b(ADDR_W),
        .numwords_a(ROWS), .numwords_b(ROWS),
        .width_byteena_a(1), .width_byteena_b(1),
        .address_reg_b("CLOCK0"), .rdcontrol_reg_b("CLOCK0"),
        .outdata_reg_b("UNREGISTERED"), .outdata_aclr_b("NONE"),
        .clock_enable_input_a("BYPASS"), .clock_enable_input_b("BYPASS"),
        .clock_enable_output_a("BYPASS"), .clock_enable_output_b("BYPASS"),
        .read_during_write_mode_mixed_ports("OLD_DATA"),
        .power_up_uninitialized("TRUE"), .lpm_type("altsyncram")
    ) u_memory (
        .clock0(clk), .clock1(1'b1),
        .clocken0(1'b1), .clocken1(1'b1), .clocken2(1'b1), .clocken3(1'b1),
        .aclr0(1'b0), .aclr1(1'b0),
        .address_a(wr_addr), .address_b(rd_addr),
        .addressstall_a(1'b0), .addressstall_b(1'b0),
        .data_a(wr_data), .data_b({WIDTH{1'b0}}),
        .wren_a(wr_en), .wren_b(1'b0), .rden_a(1'b0), .rden_b(rd_en),
        .byteena_a(1'b1), .byteena_b(1'b1),
        .q_a(), .q_b(rd_data), .eccstatus()
    );
endmodule
