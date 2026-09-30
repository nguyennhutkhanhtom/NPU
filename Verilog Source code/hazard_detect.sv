module hazard_detect(
    input logic multicycle_busy,
    input logic memory_busy,
    output logic pc_enable, fd_enable, de_enable, em_enable, mw_enable,
    output logic flush_younger
);
    always_comb begin
        pc_enable = !(multicycle_busy || memory_busy);
        fd_enable = pc_enable;de_enable = pc_enable;em_enable = 1'b1;mw_enable = 1'b1;
        flush_younger = multicycle_busy || memory_busy;
    end
endmodule
