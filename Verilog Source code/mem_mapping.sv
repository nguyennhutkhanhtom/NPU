module mem_mapping #(
    parameter DATA_WIDTH = 16,
    parameter MEM_DEPTH  = 2**19,
    parameter INIT_FILE = "mem_init.mem"
)(
    input  logic                           clk, rst_n,
    input  logic [DATA_WIDTH*32-1:0]         data_in,
    input  logic [2:0]                       r_addr_0, r_addr_1, w_addr,
    input  logic                           w_en, rd_en_0, rd_en_1,
    input  logic                           rd_type, tmatmul_write,
    
    output logic                           read_finish, write_finish, fifo_1_empty,
    output logic [DATA_WIDTH*32-1:0]         data_out_0,
    output logic [DATA_WIDTH*32-1:0]         data_out_1,
    output logic                           almost_full, almost_empty,
    input logic                            matrix_ready, ternary_ready,
    output logic                           matrix_valid, ternary_valid, tmatmul_ready,
    output wire                            transaction_busy
);

    //----------------------------------------------------------
    // Memory Array and Internal Signals
    //----------------------------------------------------------
    // Memory array initialization
    logic [DATA_WIDTH*32-1:0] mem [0:MEM_DEPTH-1];
    // synthesis translate_off
    initial begin
        if (INIT_FILE != "") $readmemh(INIT_FILE, mem);
    end
    // synthesis translate_on

    // TMATMUL owns the memory ports for one complete transaction. Port 0
    // streams row-major weights; port 1 streams the activation vector.
    // The independent read buffers retain data through engine backpressure.
    localparam int TM_MATRIX_WORDS = (512*512 + DATA_WIDTH*16-1)/(DATA_WIDTH*16);
    localparam int TM_PTR_WIDTH = (MEM_DEPTH > 1) ? $clog2(MEM_DEPTH) : 1;
    localparam int TM_COUNT_WIDTH = $clog2(TM_MATRIX_WORDS+1);
    logic tm_active, tm_seen, tm_read_finish, tm_write_finish;
    logic [TM_PTR_WIDTH-1:0] tm_weight_ptr, tm_matrix_ptr, tm_write_ptr;
    logic [TM_COUNT_WIDTH-1:0] tm_weight_count;
    logic [4:0] tm_matrix_count, tm_write_count;
    logic [DATA_WIDTH*32-1:0] tm_weights, tm_matrix;

    assign tmatmul_ready = tm_active && tm_write_count < 16;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tm_active <= 1'b0;
            tm_seen <= 1'b0;
            tm_read_finish <= 1'b0;
            tm_write_finish <= 1'b0;
            ternary_valid <= 1'b0;
            matrix_valid <= 1'b0;
            tm_weight_ptr <= '0;
            tm_matrix_ptr <= '0;
            tm_write_ptr <= '0;
            tm_weight_count <= '0;
            tm_matrix_count <= '0;
            tm_write_count <= '0;
        end
        else begin
            tm_write_finish <= 1'b0;
            if (!rd_type) tm_seen <= 1'b0;
            if (rd_type && !tm_seen) begin
                tm_active <= 1'b1;
                tm_seen <= 1'b1;
                tm_read_finish <= 1'b0;
                ternary_valid <= 1'b0;
                matrix_valid <= 1'b0;
                tm_weight_ptr <= TM_PTR_WIDTH'(1024 + int'(r_addr_0)*TM_MATRIX_WORDS);
                tm_matrix_ptr <= TM_PTR_WIDTH'(int'(r_addr_1)*16);
                tm_write_ptr <= TM_PTR_WIDTH'(int'(w_addr)*16);
                tm_weight_count <= '0;
                tm_matrix_count <= '0;
                tm_write_count <= '0;
            end
            else if (tm_active) begin
                if (!ternary_valid || ternary_ready) begin
                    ternary_valid <= tm_weight_count < TM_MATRIX_WORDS;
                    if (tm_weight_count < TM_MATRIX_WORDS) begin
                        tm_weight_ptr <= tm_weight_ptr + 1'b1;
                        tm_weight_count <= tm_weight_count + 1'b1;
                    end
                end
                if (!matrix_valid || matrix_ready) begin
                    matrix_valid <= tm_matrix_count < 16;
                    if (tm_matrix_count < 16) begin
                        tm_matrix_ptr <= tm_matrix_ptr + 1'b1;
                        tm_matrix_count <= tm_matrix_count + 1'b1;
                    end
                end
                if (tm_weight_count == TM_MATRIX_WORDS && (!ternary_valid || ternary_ready) &&
                    tm_matrix_count == 16 && (!matrix_valid || matrix_ready))
                    tm_read_finish <= 1'b1;
                if (tmatmul_write && tmatmul_ready) begin
                    tm_write_ptr <= tm_write_ptr + 1'b1;
                    tm_write_count <= tm_write_count + 1'b1;
                    if (tm_write_count == 15) begin
                        tm_active <= 1'b0;
                        tm_write_finish <= 1'b1;
                    end
                end
            end
        end
    end
    always_ff @(posedge clk) begin
        if (tm_active && (!ternary_valid || ternary_ready) && tm_weight_count < TM_MATRIX_WORDS)
            tm_weights <= mem[tm_weight_ptr];
        if (tm_active && (!matrix_valid || matrix_ready) && tm_matrix_count < 16)
            tm_matrix <= mem[tm_matrix_ptr];
    end

    // synthesis translate_off
    always @(posedge clk) begin
        if (rst_n && rd_type && !tm_seen &&
            (1024 + (int'(r_addr_0)+1)*TM_MATRIX_WORDS > MEM_DEPTH || DATA_WIDTH < 1))
            $fatal(1, "TMATMUL memory range exceeds MEM_DEPTH");
    end
    // synthesis translate_on

    // Pointer declarations
    logic [18:0] w_ptr, r_ptr_0, r_ptr_1;
    logic [18:0] w_ptr_next, r_ptr_0_next, r_ptr_1_next;
    logic [18:0] w_ptr_end, r_ptr_0_end, r_ptr_1_end;
    
    // FIFO status signals
    logic fifo_full, fifo_empty_0, fifo_empty_1;
    logic [18:0] v_index;
    
    // Address decode signals
    logic [18:0] r_addr_0_decode, r_addr_1_decode, w_addr_decode;


    //----------------------------------------------------------
    // Address Decoding
    //----------------------------------------------------------
    // For port 0, decode based on rd_type.
    always_comb begin
        if (rd_type) begin
            case(r_addr_0)
                3'd0: r_addr_0_decode = 19'd0;
                3'd1: r_addr_0_decode = 19'd1024;
                3'd2: r_addr_0_decode = 19'd2048;
                3'd3: r_addr_0_decode = 19'd3072;
                3'd4: r_addr_0_decode = 19'd4096;
                3'd5: r_addr_0_decode = 19'd5120;
                3'd6: r_addr_0_decode = 19'd6144;
                3'd7: r_addr_0_decode = 19'd7168;
                default: r_addr_0_decode = 19'd0;
            endcase
        end else begin
            case(r_addr_0)
                3'd0: r_addr_0_decode = 19'd0 + v_index;
                3'd1: r_addr_0_decode = 19'd16 + v_index;
                3'd2: r_addr_0_decode = 19'd32 + v_index;
                3'd3: r_addr_0_decode = 19'd48 + v_index;
                3'd4: r_addr_0_decode = 19'd64 + v_index;
                3'd5: r_addr_0_decode = 19'd80 + v_index;
                3'd6: r_addr_0_decode = 19'd96 + v_index;
                3'd7: r_addr_0_decode = 19'd112 + v_index;
                default: r_addr_0_decode = 19'd0;
            endcase
        end
    end

    // For port 1: fixed decode offsets
    always_comb begin
        if(rd_type) begin
            v_index = '0;
        end else begin
            v_index = r_addr_1[2:0] * 7'd128;
        end
    end

    always_comb begin
        case(r_addr_1)
            3'd0: r_addr_1_decode = 19'd1024;
            3'd1: r_addr_1_decode = 19'd1040;
            3'd2: r_addr_1_decode = 19'd1056;
            3'd3: r_addr_1_decode = 19'd1072;
            3'd4: r_addr_1_decode = 19'd1088;
            3'd5: r_addr_1_decode = 19'd1104;
            3'd6: r_addr_1_decode = 19'd1120;
            3'd7: r_addr_1_decode = 19'd1136;
            default: r_addr_1_decode = 19'd0;
        endcase
    end

    // Write port decode
    always_comb begin
        case(w_addr)
            3'd0: w_addr_decode = 19'd0 + v_index;
            3'd1: w_addr_decode = 19'd16 + v_index;
            3'd2: w_addr_decode = 19'd32 + v_index;
            3'd3: w_addr_decode = 19'd48 + v_index;
            3'd4: w_addr_decode = 19'd64 + v_index;
            3'd5: w_addr_decode = 19'd80 + v_index;
            3'd6: w_addr_decode = 19'd96 + v_index;
            3'd7: w_addr_decode = 19'd112 + v_index;
            default: w_addr_decode = 19'd0;
        endcase
    end

    // Calculate pointer endpoint values
    always_comb begin
        r_ptr_0_end = rd_type ? (r_addr_0_decode + 19'd1023)
                              : (r_addr_0_decode + 19'd15);
        r_ptr_1_end = r_addr_1_decode + 19'd15;
        
    end


    //----------------------------------------------------------
    // State Machines for FIFO Read and Write
    //----------------------------------------------------------
    // Define states for READ FSM
    localparam IDLE_READ  = 2'b00,
               FETCH_READ = 2'b01,
               RUN_READ   = 2'b10;
    logic [1:0] state_read, next_state_read;
    // Generate a reset signal for read pointers when in idle
    assign reset_ptr_read = (state_read == IDLE_READ) ? 1'b0 : 1'b1;

    // READ state machine
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state_read <= IDLE_READ;
        else if (rd_type)
            state_read <= IDLE_READ;
        else
            state_read <= next_state_read;
    end

    always_comb begin
        case (state_read)
            IDLE_READ:  next_state_read = (rd_en_0 || rd_en_1) ? FETCH_READ : IDLE_READ;
            FETCH_READ: next_state_read = RUN_READ;
            RUN_READ:   next_state_read = (fifo_empty_0) ? IDLE_READ : RUN_READ;
            default:    next_state_read = IDLE_READ;
        endcase
    end

    // Define states for WRITE FSM
    localparam IDLE_WRITE  = 2'b00,
               FETCH_WRITE = 2'b01,
               RUN_WRITE   = 2'b10;
    logic [1:0] state_write, next_state_write;
    assign transaction_busy = tm_active || (state_read != IDLE_READ) ||
                              (state_write != IDLE_WRITE);
    assign reset_ptr_write = (state_write == IDLE_WRITE) ? 1'b0 : 1'b1;

    // WRITE state machine
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state_write <= IDLE_WRITE;
        else if (rd_type)
            state_write <= IDLE_WRITE;
        else
            state_write <= next_state_write;
    end

    logic wr_state_change;
    always_comb begin
        if(rd_type)
            wr_state_change = fifo_full & read_finish;
        else
            wr_state_change = fifo_full;
    end

    always_comb begin
        case (state_write)
            IDLE_WRITE:  next_state_write = (w_en) ? FETCH_WRITE : IDLE_WRITE;
            FETCH_WRITE: next_state_write = RUN_WRITE;
            RUN_WRITE:   next_state_write = (wr_state_change) ? IDLE_WRITE : RUN_WRITE;
            default:     next_state_write = IDLE_WRITE;
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            w_ptr_end <= '0;
        end
        else if (state_write == FETCH_WRITE) begin
            w_ptr_end = w_addr_decode + 19'd15;
        end
    end


    //----------------------------------------------------------
    // Pointer and Memory Update Logic
    //----------------------------------------------------------
    logic w_ptr_enable;
    //Write pointer enable
    assign w_ptr_enable = (state_write == RUN_WRITE) && !fifo_full && (!rd_type || tmatmul_write);

    // Write pointer update
    always_ff @(posedge clk or negedge reset_ptr_write) begin
        if (!reset_ptr_write)
            w_ptr <= '0;
        else if (state_write == FETCH_WRITE)
            w_ptr <= w_addr_decode;
        else if (w_ptr_enable)
            w_ptr <= w_ptr_next;
    end

    // Write data into memory
    always_ff @(posedge clk) begin
        if (rst_n && tmatmul_write && tmatmul_ready)
            mem[tm_write_ptr] <= data_in;
        // RUN_WRITE includes the final word at w_ptr_end. The FSM exits on
        // this edge; excluding fifo_full here silently loses stored lane 480+.
        else if (!rd_type && !tm_active && w_en && (state_write == RUN_WRITE))
            mem[w_ptr] <= data_in;
    end

    // Increment the write pointer
    assign w_ptr_next = w_ptr + 3'b01;


    // Read port 0: Pointer update and output assignment
    always_ff @(posedge clk or negedge reset_ptr_read) begin
        if (!reset_ptr_read)
            r_ptr_0 <= '0;
        else if (state_read == FETCH_READ)
            r_ptr_0 <= r_addr_0_decode;
        else if (!fifo_empty_0 && (state_read == RUN_READ))
            r_ptr_0 <= r_ptr_0_next;
    end

    assign r_ptr_0_next = r_ptr_0 + 3'b01;
    assign data_out_0   = rd_type ? tm_weights : mem[r_ptr_0];

    // Read port 1: Pointer update and output assignment
    always_ff @(posedge clk or negedge reset_ptr_read) begin
        if (!reset_ptr_read)
            r_ptr_1 <= '0;
        else if (state_read == FETCH_READ | fifo_empty_1)
            r_ptr_1 <= r_addr_1_decode;
        else if (!fifo_empty_0 && (state_read == RUN_READ))
            r_ptr_1 <= r_ptr_1_next;
    end

    assign r_ptr_1_next = r_ptr_1 + 3'b01;
    assign data_out_1   = rd_type ? tm_matrix : mem[r_ptr_1];


    //----------------------------------------------------------
    // Status Signals and Finishing Flags
    //----------------------------------------------------------
    // FIFO full/empty flags based on pointer endpoints
    assign fifo_full     = (w_ptr == w_ptr_end);
    assign fifo_empty_0  = (r_ptr_0 == r_ptr_0_end);
    assign fifo_empty_1  = (r_ptr_1 == r_ptr_1_end);
    assign fifo_1_empty  = fifo_empty_1;

    // Almost full and almost empty signals
    always_comb begin
        almost_full  = (w_ptr == (w_addr_decode + 10'd12));
        if (rd_type)
            almost_empty = (r_ptr_0 == (r_addr_0_decode + 19'd1020));
        else
            almost_empty = (r_ptr_0 == (r_addr_0_decode + 10'd12));
    end

    // Read and write finish flags
    assign read_finish  = rd_type ? tm_read_finish : fifo_empty_0;
    assign write_finish = rd_type ? tm_write_finish : fifo_full;

endmodule
