module descriptor_file (
    input logic clk,
    input logic rst_n,
    input logic host_we,
    input logic [2:0] host_id,
    input logic host_is_matrix,
    input logic [1:0] host_word_sel,
    input logic [31:0] host_wdata,
    output logic [31:0] host_rdata,

    input logic [2:0] ws_id0,
    input logic [2:0] ws_id1,
    input logic [2:0] ws_id2,
    output npu_pkg::ws_desc_t ws_desc0,
    output npu_pkg::ws_desc_t ws_desc1,
    output npu_pkg::ws_desc_t ws_desc2,
    input logic [2:0] mat_id,
    output npu_pkg::mat_desc_t mat_desc
);
    import npu_pkg::*;
    ws_desc_t ws [0:7];
    mat_desc_t md [0:7];

    assign ws_desc0 = ws[ws_id0];
    assign ws_desc1 = ws[ws_id1];
    assign ws_desc2 = ws[ws_id2];
    assign mat_desc = md[mat_id];

    always_comb begin
        if (!host_is_matrix)
            host_rdata = ws[host_id];
        else begin
            case (host_word_sel)
                2'h0 : host_rdata = md[host_id][31:0];
                2'h1 : host_rdata = md[host_id][63:32];
                2'h2 : host_rdata = md[host_id][95:64];
                default : host_rdata = '0;
            endcase
        end
    end

    // Constant array indexes and whole-word writes avoid Quartus 18.1
    // treating partial writes to a dynamically indexed packed struct as latches.
    genvar entry, word_index;
    generate
    for (entry = 0; entry < 8; entry = entry + 1) begin : g_descriptor
        logic [95:0] matrix_bits;
        assign md[entry] = mat_desc_t'(matrix_bits);

        always_ff @(posedge clk or negedge rst_n) begin
            if (!rst_n)
                ws[entry] <= '0;
            else if (host_we && !host_is_matrix && host_id == 3'(entry))
                ws[entry] <= ws_desc_t'(host_wdata);
        end

        for (word_index = 0; word_index < 3; word_index = word_index + 1) begin : g_word
            logic [31:0] word_q;
            assign matrix_bits[word_index * 32 +: 32] = word_q;
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n)
                    word_q <= '0;
                else if (host_we && host_is_matrix && host_id == 3'(entry) &&
                         host_word_sel == 2'(word_index))
                    word_q <= host_wdata;
            end
        end
    end
    endgenerate
endmodule
