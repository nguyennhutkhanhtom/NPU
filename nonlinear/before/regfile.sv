module register #(
    parameter DATA_WIDTH = 16,
    parameter ADDR_WIDTH = 3,
	 parameter MEM_DEPTH = 1024
)(
    input logic clk, rst_n,
    input logic [DATA_WIDTH*32-1:0]  data_in,
    input logic [ADDR_WIDTH-1:0] r_addr_0, r_addr_1, w_addr,
    input logic w_en, rd_en,
    // input logic mul_type,
    
    output logic full, empty,
    output logic [DATA_WIDTH*32-1:0] data_out_0,
    output logic [DATA_WIDTH*32-1:0] data_out_1,
    output logic almost_full, almost_empty
);

    // Internal parameters and signals

    logic [DATA_WIDTH*32-1:0] mem [0:MEM_DEPTH-1];
    logic [18:0] w_ptr, r_ptr_0, r_ptr_1;
    logic fifo_full, fifo_empty_0, fifo_empty_1;

    logic [18:0] r_ptr_0_end, r_ptr_1_end, w_ptr_end;
    logic [18:0] w_ptr_next, r_ptr_0_next, r_ptr_1_next;

    logic [18:0] r_addr_0_decode, r_addr_1_decode, w_addr_decode;
    // Address decode
    logic [1:0] state_write, next_state_write;
    parameter IDLE_WRITE = 2'b00, FETCH_WRITE= 2'b01, RUN_WRITE = 2'b10;

    logic [1:0] state_read, next_state_read;
    parameter IDLE_READ = 2'b00, FETCH_READ= 2'b01, RUN_READ = 2'b10;

    always_comb begin: read_0_decode
        case(r_addr_0)
            0: r_addr_0_decode = 0;
            1: r_addr_0_decode = 16;
            2: r_addr_0_decode = 32;
            3: r_addr_0_decode = 48;
            4: r_addr_0_decode = 64;
            5: r_addr_0_decode = 80;
            6: r_addr_0_decode = 96;
            7: r_addr_0_decode = 112;
        endcase
    end

    always_comb begin: read_1_decode
        case(r_addr_1)
            0: r_addr_1_decode = 0;
            1: r_addr_1_decode = 16;
            2: r_addr_1_decode = 32;
            3: r_addr_1_decode = 48;
            4: r_addr_1_decode = 64;
            5: r_addr_1_decode = 80;
            6: r_addr_1_decode = 96;
            7: r_addr_1_decode = 112;
        endcase
    end

    always_comb begin: write_decode
        case(w_addr)
            0: w_addr_decode = 0;
            1: w_addr_decode = 16;
            2: w_addr_decode = 32;
            3: w_addr_decode = 48;
            4: w_addr_decode = 64;
            5: w_addr_decode = 80;
            6: w_addr_decode = 96;
            7: w_addr_decode = 112;
        endcase
    end

    // always_comb begin
    //     r_ptr_0_end = r_addr_0_decode + 10'd15;
    //     r_ptr_1_end = r_addr_1_decode + 10'd15;
    // end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_ptr_0_end <= '0;
            r_ptr_1_end <= '0;
        end else if(state_read == FETCH_READ) begin
            r_ptr_0_end <= r_addr_0_decode + 10'd15;
            r_ptr_1_end <= r_addr_1_decode + 10'd15;
        end
    end
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            w_ptr_end <= '0;
        end else if(state_write == FETCH_WRITE) begin
            w_ptr_end <= w_addr_decode + 10'd15;
        end
    end

    // stage machine for FIFO READ
    
    logic reset_ptr_read;
    assign reset_ptr_read = ~(state_read == IDLE_READ);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state_read <= IDLE_READ;
        else
            state_read <= next_state_read;
    end

    always_comb begin
        case(state_read)
            IDLE_READ: begin
                if(rd_en)
                    next_state_read = FETCH_READ;
                else
                    next_state_read = IDLE_READ;
            end
            FETCH_READ: begin
                next_state_read = RUN_READ;
            end
            RUN_READ: begin
                if(fifo_empty_0)
                    next_state_read = IDLE_READ;
                else
                    next_state_read = RUN_READ;
            end
        endcase
    end

    // state machine for FIFO WRITE
    
    logic reset_ptr_write;
    assign reset_ptr_write = ~(state_write == IDLE_WRITE);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state_write <= IDLE_WRITE;
        else
            state_write <= next_state_write;
    end

    always_comb begin
        case(state_write)
            IDLE_WRITE: begin
                if(w_en)
                    next_state_write = FETCH_WRITE;
                else
                    next_state_write = IDLE_WRITE;
            end
            FETCH_WRITE: begin
                next_state_write = RUN_WRITE;
            end
            RUN_WRITE: begin
                if(fifo_full)
                    next_state_write = IDLE_WRITE;
                else
                    next_state_write = RUN_WRITE;
            end
        endcase
    end

    // Write logic
    always_ff @(posedge clk or negedge reset_ptr_write) begin
        if (!reset_ptr_write)
            w_ptr <= '0;
        else begin
            if(state_write == FETCH_WRITE)
                w_ptr <= w_addr_decode;
            else if (!fifo_full && state_write == RUN_WRITE) begin
                w_ptr <= w_ptr_next;
            end
        end
    end

    always_ff @(posedge clk) begin
        if (state_write == RUN_WRITE) begin
            mem[w_ptr] <= data_in;
        end
    end

    assign w_ptr_next = w_ptr + 3'b01;

    // Read logic for port 0
    always_ff @(posedge clk or negedge reset_ptr_read) begin
        if (!reset_ptr_read)
            r_ptr_0 <= '0;
        else begin
            if(state_read == FETCH_READ) begin
                r_ptr_0 <= r_addr_0_decode;
            end
            else if (!fifo_empty_0 && state_read == RUN_READ) begin
                r_ptr_0 <= r_ptr_0_next;
            end
        end
    end

    assign r_ptr_0_next = r_ptr_0 + 3'b01;
    assign data_out_0 = mem[r_ptr_0];

    // Read logic for port 1
    always_ff @(posedge clk or negedge reset_ptr_read) begin
        if (!reset_ptr_read)
            r_ptr_1 <= '0;
        else begin
            if(state_read == FETCH_READ) 
                r_ptr_1 <= r_addr_1_decode;
            else if (!fifo_empty_1 && state_read == RUN_READ) begin
                r_ptr_1 <= r_ptr_1_next;
            end
        end
    end

    assign r_ptr_1_next = r_ptr_1 + 3'b01;
    assign data_out_1 = mem[r_ptr_1];

    // FIFO status signals
    assign fifo_full = (w_ptr == w_ptr_end);
    assign fifo_empty_0 = (r_ptr_0 == r_ptr_0_end);
    assign fifo_empty_1 = (r_ptr_1 == r_ptr_1_end);

    // Almost full and empty signals
    assign almost_full = (w_ptr == (w_addr_decode + 10'd12));
    assign almost_empty = (r_ptr_0 == (r_addr_0_decode + 10'd12));
    // Read finish signal
    assign empty = fifo_empty_0;
    
    //write finish signal
    assign full = fifo_full;

endmodule
