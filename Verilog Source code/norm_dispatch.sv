module norm_dispatch (
    input logic clk,
    input logic rst_n,
    input logic start,
    input npu_pkg::ws_desc_t src_desc,
    input npu_pkg::ws_desc_t dst_desc,
    input logic [7:0] scratch_z_base,
    input logic [63:0] epsilon_raw32,
    input logic [23:0] delta_raw,

    output logic ws_rd_en,
    output logic [7:0] ws_rd_addr,
    input logic [255:0] ws_rd_data,
    input logic ws_rd_valid,
    output logic ws_wr_en,
    output logic [7:0] ws_wr_addr,
    output logic [255:0] ws_wr_data,

    output logic busy,
    output logic done,
    output logic overflow,
    output logic format_error,
    output logic [23:0] quant_d,
    output logic [23:0] norm_m,
    output logic [5:0] norm_r,
    output logic [23:0] quant_m,
    output logic [5:0] quant_r
);
    import npu_pkg::*;
    logic invalid, rejected, core_busy, core_done, core_error;
    always_comb begin
        invalid = !ws_valid(src_desc) || !ws_valid(dst_desc) ||
        src_desc.fmt != FMT_S16 || dst_desc.fmt != FMT_S8 ||
        src_desc.length != dst_desc.length;
    end
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) rejected <= 0;
        else rejected <= start && !core_busy && invalid;
    end
    assign busy = core_busy;
    assign done = core_done || rejected;
    assign format_error = core_error || rejected;
    norm u_norm(
        .clk(clk),
        .rst_n(rst_n),
        .start(start && !invalid),
        .x_base(src_desc.base_word),
        .z_base(scratch_z_base),
        .q_base(dst_desc.base_word),
        .k_len(src_desc.length),
        .epsilon_raw32(epsilon_raw32),
        .delta_raw(delta_raw),
        .ws_rd_en(ws_rd_en),
        .ws_rd_addr(ws_rd_addr),
        .ws_rd_data(ws_rd_data),
        .ws_rd_valid(ws_rd_valid),
        .ws_wr_en(ws_wr_en),
        .ws_wr_addr(ws_wr_addr),
        .ws_wr_data(ws_wr_data),
        .busy(core_busy),
        .done(core_done),
        .overflow(overflow),
        .format_error(core_error),
        .quant_d(quant_d),
        .norm_m(norm_m),
        .norm_r(norm_r),
        .quant_m(quant_m),
        .quant_r(quant_r)
    );
endmodule
