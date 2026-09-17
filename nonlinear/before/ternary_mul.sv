//Ternary Matrix Multiplication
module ternary_mul(
    input clk, rst_n, enable,
    input logic [511:0] matrix_in,
    input logic [511:0] ternary_matrix,
    output logic [511:0] matrix_out,
    input logic read_finish,
    output logic tmatmul_write
);
    logic [511:0] tmatrix [1023:0];
    logic [511:0] matrix_x [15:0];

    // pointer for ternary matrix and matrix in
    logic [9:0] tmat_ptr;
    logic [3:0] mat_ptr;
    
    // assign the input matrix and ternary matrix to the arrays
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < 1024; i = i + 1) begin
                tmatrix[i] <= '0;
            end
            for (int j = 0; j < 16; j = j + 1) begin
                matrix_x[j] <= '0;
            end
        end
        else if (enable) begin
            tmatrix[tmat_ptr] <= ternary_matrix;
            matrix_x[mat_ptr] <= matrix_in;
        end
    end

    // pointer update logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tmat_ptr <= '0;
            mat_ptr <= '0;
        end
        else if (enable) begin
            tmat_ptr <= tmat_ptr + 1;
            mat_ptr <= mat_ptr + 1;
        end
    end
    
    //assign tmatrix and matrix_in to the arrays for easy access
    logic [1:0] tmatrix_data [262143:0];
    logic [15:0] matrix_in_data [511:0];
    genvar i, j;

    generate
        for (i = 0; i < 1024; i = i + 1) begin : tmatrix_assign
            for (j = 0; j < 256; j = j + 1) begin
                assign tmatrix_data[i * 512 + j] = tmatrix[i][j * 2 +: 2];
            end
        end
        for (i = 0; i < 512; i = i + 1) begin : matrix_in_assign
            assign matrix_in_data[i] = matrix_x[i / 32][(i % 32) * 16 +: 16];
        end
    endgenerate

    // Ternary matrix multiplication logic
    genvar row, col;
    logic [15:0] mul_result [262143:0]; // 262144 results for 512x512 multiplication
    generate
        for (row = 0; row < 512; row = row + 1) begin : row_loop
            for (col = 0; col < 512; col = col + 1) begin : col_loop
                always_comb begin : ternary_mul_logic
                    case (tmatrix_data[row * 512 + col])
                        2'b01: mul_result[row * 512 + col] = matrix_in_data[col];
                        2'b11: mul_result[row * 512 + col] = -matrix_in_data[col];
                        default: mul_result[row * 512 + col] = '0;
                    endcase
                end
            end
        end
    endgenerate


    // Accumulate the results
    logic [15:0] matrix_result [511:0];

    generate
        for(j = 0; j < 512; j = j + 1) begin
            acc_mul acc_inst (
                .mul_result(mul_result[j * 512 +: 512]),
                .acc_result(matrix_result[j])
            );
        end
    endgenerate

    // Output the final result

    // update pointer for writing the result
    logic write_enable;
    logic [3:0] write_ptr;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            write_enable <= 1'b0;
        end
        else if (read_finish) begin
            write_enable <= 1'b1;
        end
        else if(|write_ptr) begin
            write_enable <= 1'b0;
        end

    end

    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            write_ptr <= '0;
        end
        else if (write_enable) begin
            write_ptr <= write_ptr + 1;
        end
    end

    // Assign the result to the output matrix
    assign matrix_out = {matrix_result[0 + write_ptr*32], matrix_result[1 + write_ptr*32], 
                         matrix_result[2 + write_ptr*32], matrix_result[3 + write_ptr*32],
                         matrix_result[4 + write_ptr*32], matrix_result[5 + write_ptr*32],
                         matrix_result[6 + write_ptr*32], matrix_result[7 + write_ptr*32],
                         matrix_result[8 + write_ptr*32], matrix_result[9 + write_ptr*32],
                         matrix_result[10 + write_ptr*32], matrix_result[11 + write_ptr*32],
                         matrix_result[12 + write_ptr*32], matrix_result[13 + write_ptr*32],
                         matrix_result[14 + write_ptr*32], matrix_result[15 + write_ptr*32],
                         matrix_result[16 + write_ptr*32], matrix_result[17 + write_ptr*32],
                         matrix_result[18 + write_ptr*32], matrix_result[19 + write_ptr*32],
                            matrix_result[20 + write_ptr*32], matrix_result[21 + write_ptr*32],
                            matrix_result[22 + write_ptr*32], matrix_result[23 + write_ptr*32],
                            matrix_result[24 + write_ptr*32], matrix_result[25 + write_ptr*32],
                            matrix_result[26 + write_ptr*32], matrix_result[27 + write_ptr*32],
                            matrix_result[28 + write_ptr*32], matrix_result[29 + write_ptr*32],
                            matrix_result[30 + write_ptr*32], matrix_result[31 + write_ptr*32]};

    //signal for writing the result
    assign tmatmul_write = write_enable;

endmodule
