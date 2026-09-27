// A register bank contains 16 words. NORM applies the 32-lane RMS operation
// independently to each word. Source/destination descriptors remain latched
// until all 16 writes commit, including in-place and consecutive instructions.
module norm_dispatch #(
    parameter LUT_FILE = "data/normContent.mif"
)(
    input logic clk, rst_n,
    input logic [12:0] instruction,
    input logic [8:0] instruction_pc,
    input logic pipeline_idle,
    output wire hold_front, advance_pc, own_register,
    output wire [9:0] read_address, write_address,
    input logic [511:0] read_data,
    output wire [511:0] write_data,
    output wire write_enable, done,
    output logic overflow,
    output logic [12:0] active_instruction,
    output logic [8:0] active_pc
);
    typedef enum logic [2:0] {IDLE, DRAIN, START_WORD, WAIT_WORD, WRITE_WORD, RETIRE} state_t;
    state_t state;
    logic [3:0] word_index;
    logic [6:0] source_base, dest_base;
    wire request = (instruction[12:9] == 4'b0111);
    wire word_done, word_overflow;
    wire [15:0] samples [31:0], results [31:0];

    assign hold_front = request || (state != IDLE);
    assign advance_pc = (state == RETIRE);
    assign own_register = (state == START_WORD || state == WAIT_WORD || state == WRITE_WORD);
    assign read_address = {3'b0, source_base} + {6'b0, word_index};
    assign write_address = {3'b0, dest_base} + {6'b0, word_index};
    assign write_enable = rst_n && (state == WRITE_WORD);
    assign done = (state == RETIRE);

    for (genvar lane = 0; lane < 32; lane++) begin : pack_lanes
        assign samples[lane] = read_data[16*lane +: 16];
        assign write_data[16*lane +: 16] = results[lane];
    end
    norm #(.LUT_FILE(LUT_FILE)) rms (
        .clk(clk), .rst_n(rst_n), .start(state == START_WORD),
        .x(samples), .out(results), .busy(), .done(word_done), .overflow(word_overflow)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            word_index <= 0;
            source_base <= 0;
            dest_base <= 0;
            overflow <= 0;
            active_instruction <= 0;
            active_pc <= 0;
        end else begin
            case (state)
                IDLE: if (request) begin
                    active_instruction <= instruction;
                    active_pc <= instruction_pc;
                    source_base <= {instruction[2:0], 4'b0};
                    dest_base <= {instruction[8:6], 4'b0};
                    word_index <= 0;
                    overflow <= 0;
                    state <= DRAIN;
                end
                DRAIN: if (pipeline_idle) state <= START_WORD;
                START_WORD: state <= WAIT_WORD;
                WAIT_WORD: if (word_done) begin
                    overflow <= overflow | word_overflow;
                    state <= WRITE_WORD;
                end
                WRITE_WORD: begin
                    if (word_index == 15) state <= RETIRE;
                    else begin
                        word_index <= word_index + 1'b1;
                        state <= START_WORD;
                    end
                end
                RETIRE: state <= IDLE;
                default: state <= IDLE;
            endcase
        end
    end
endmodule
