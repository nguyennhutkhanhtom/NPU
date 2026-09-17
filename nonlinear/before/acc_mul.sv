module acc_mul(
    input logic [15:0] mul_result [511:0], // 16-bit results for 262144 multiplications
    output logic [15:0] acc_result
);

    // Accumulate the results
    logic [15:0] stage_0 [255:0];
    logic [15:0] stage_1 [127:0];
    logic [15:0] stage_2 [63:0];
    logic [15:0] stage_3 [31:0];
    logic [15:0] stage_4 [15:0];
    logic [15:0] stage_5 [7:0];
    logic [15:0] stage_6 [3:0];
    logic [15:0] stage_7 [1:0];

    // Stage 0: Pairwise addition
    always_comb begin
        for (int i = 0; i < 256; i++) begin
            stage_0[i] = mul_result[i * 2] + mul_result[i * 2 + 1];
        end
    end

    // Stage 1: Pairwise addition
    always_comb begin
        for (int i = 0; i < 128; i++) begin
            stage_1[i] = stage_0[i * 2] + stage_0[i * 2 + 1];
        end
    end

    // Stage 2: Pairwise addition
    always_comb begin
        for (int i = 0; i < 64; i++) begin
            stage_2[i] = stage_1[i * 2] + stage_1[i * 2 + 1];
        end
    end

    // Stage 3: Pairwise addition
    always_comb begin
        for (int i = 0; i < 32; i++) begin
            stage_3[i] = stage_2[i * 2] + stage_2[i * 2 + 1];
        end
    end

    // Stage 4: Pairwise addition
    always_comb begin
        for (int i = 0; i < 16; i++) begin
            stage_4[i] = stage_3[i * 2] + stage_3[i * 2 + 1];
        end
    end

    // Stage 5: Pairwise addition
    always_comb begin
        for (int i = 0; i < 8; i++) begin
            stage_5[i] = stage_4[i * 2] + stage_4[i * 2 + 1];
        end
    end

    // Stage 6: Pairwise addition
    always_comb begin
        for (int i = 0; i < 4; i++) begin
            stage_6[i] = stage_5[i * 2] + stage_5[i * 2 + 1];
        end
    end

    // Stage 7: Final addition
    always_comb begin
        for (int i = 0; i < 2; i++) begin
            stage_7[i] = stage_6[i * 2] + stage_6[i * 2 + 1];
        end
    end

    // Final result
    always_comb begin
        acc_result = stage_7[0] + stage_7[1];
    end
endmodule
