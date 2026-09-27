// A register bank contains 16 words.
// NORM applies the 32-lane RMS operation independently to each word.
// Source/destination descriptors remain latched until all 16 writes commit,
// including in-place and consecutive instructions.

module norm_dispatch #(
    parameter LUT_FILE = "datanormContent.mif"
)(
    input  logic         clk,
    input  logic         rst_n,

    input  logic [12:0]  instruction,
    input  logic [8:0]   instruction_pc,
    input  logic         pipeline_idle,

    output wire          hold_front,
    output wire          advance_pc,
    output wire          own_register,

    output wire [9:0]    read_address,
    output wire [9:0]    write_address,

    input  logic [511:0] read_data,
    output wire  [511:0] write_data,

    output wire          write_enable,
    output wire          done,

    output logic         overflow,
    output logic [12:0]  active_instruction,
    output logic [8:0]   active_pc
);

    typedef enum logic [2:0] {
        IDLE,
        DRAIN,
        START_WORD,
        WAIT_WORD,
        WRITE_WORD,
        RETIRE
    } state_t;

    state_t state;

    logic [3:0] word_index;

    logic [6:0] source_base;
    logic [6:0] dest_base;

    wire request;

    wire word_done;
    wire word_overflow;

    wire [15:0] samples [0:31];
    wire [15:0] results [0:31];


    // ------------------------------------------------------------
    // Instruction decode
    // ------------------------------------------------------------

    assign request =
        (instruction[12:9] == 4'b0111);


    // ------------------------------------------------------------
    // Pipeline / register ownership
    // ------------------------------------------------------------

    assign hold_front =
        request || (state != IDLE);

    assign advance_pc =
        (state == RETIRE);

    assign own_register =
        (state == START_WORD) ||
        (state == WAIT_WORD)  ||
        (state == WRITE_WORD);


    // ------------------------------------------------------------
    // Register-bank addresses
    // ------------------------------------------------------------

    assign read_address =
        {3'b000, source_base}
        + {6'b000000, word_index};

    assign write_address =
        {3'b000, dest_base}
        + {6'b000000, word_index};


    // ------------------------------------------------------------
    // Write / completion control
    // ------------------------------------------------------------

    assign write_enable =
        rst_n && (state == WRITE_WORD);

    assign done =
        (state == RETIRE);


    // ------------------------------------------------------------
    // Split 512-bit word into 32 x 16-bit lanes
    // and repack NORM result back to 512 bits
    // ------------------------------------------------------------

    genvar lane;

    generate
        for (lane = 0; lane < 32; lane = lane + 1) begin : pack_lanes

            assign samples[lane] =
                read_data[16*lane +: 16];

            assign write_data[16*lane +: 16] =
                results[lane];

        end
    endgenerate


    // ------------------------------------------------------------
    // RMS NORM core
    // ------------------------------------------------------------

    norm #(
        .LUT_FILE(LUT_FILE)
    ) rms (
        .clk      (clk),
        .rst_n    (rst_n),

        .start    (state == START_WORD),

        .x        (samples),
        .out      (results),

        .busy     (),
        .done     (word_done),
        .overflow (word_overflow)
    );


    // ------------------------------------------------------------
    // Dispatcher FSM
    // ------------------------------------------------------------

    always_ff @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            state              <= IDLE;
            word_index         <= 4'd0;

            source_base        <= 7'd0;
            dest_base          <= 7'd0;

            overflow           <= 1'b0;

            active_instruction <= 13'd0;
            active_pc          <= 9'd0;

        end
        else begin

            case (state)

                // ------------------------------------------------
                // Wait for NORM instruction
                // ------------------------------------------------

                IDLE: begin

                    if (request) begin

                        active_instruction <= instruction;
                        active_pc          <= instruction_pc;

                        source_base <= {
                            instruction[2:0],
                            4'b0000
                        };

                        dest_base <= {
                            instruction[8:6],
                            4'b0000
                        };

                        word_index <= 4'd0;
                        overflow   <= 1'b0;

                        state <= DRAIN;

                    end

                end


                // ------------------------------------------------
                // Wait until previous pipeline activity is finished
                // ------------------------------------------------

                DRAIN: begin

                    if (pipeline_idle)
                        state <= START_WORD;

                end


                // ------------------------------------------------
                // Pulse start to NORM core
                // ------------------------------------------------

                START_WORD: begin

                    state <= WAIT_WORD;

                end


                // ------------------------------------------------
                // Wait for current 32-lane word to finish
                // ------------------------------------------------

                WAIT_WORD: begin

                    if (word_done) begin

                        overflow <=
                            overflow | word_overflow;

                        state <= WRITE_WORD;

                    end

                end


                // ------------------------------------------------
                // Commit normalized word back to register bank
                // ------------------------------------------------

                WRITE_WORD: begin

                    if (word_index == 4'd15) begin

                        state <= RETIRE;

                    end
                    else begin

                        word_index <=
                            word_index + 1'b1;

                        state <= START_WORD;

                    end

                end


                // ------------------------------------------------
                // Instruction completed
                // ------------------------------------------------

                RETIRE: begin

                    state <= IDLE;

                end


                default: begin

                    state <= IDLE;

                end

            endcase

        end

    end

endmodule