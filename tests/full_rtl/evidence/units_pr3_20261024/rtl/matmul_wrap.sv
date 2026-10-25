// Board wrapper: LED0=ready, LED1=saturation/overflow, LED2=error.
// The host must load SRAM, descriptors and a HALT-terminated program before start.
module matmul_wrap (
    input logic CLOCK_50,
    input logic [0:0] SW,
    output logic [2:0] LEDG,
    input logic host_en, host_we,
    input logic [31:0] host_addr, host_wdata,
    output logic [31:0] host_rdata,
    output logic host_ready
);
    logic running;
    logic [8:0] pc_debug;
    logic [12:0] instr_debug;
    matmulfree u_npu(.clk(CLOCK_50),
        .rst_n(SW[0]),
        .host_en(host_en),
        .host_we(host_we),
        .host_addr(host_addr),
        .host_wdata(host_wdata),
        .host_rdata(host_rdata),
        .host_ready(host_ready),
        .running(running),
        .ready(LEDG[0]),
        .overflow_out(LEDG[1]),
        .error(LEDG[2]),
        .pc_debug(pc_debug),
        .instr_debug(instr_debug));
endmodule
