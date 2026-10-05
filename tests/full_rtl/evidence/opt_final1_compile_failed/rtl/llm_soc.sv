// Autonomous fixed-point NanoFable inference. The host loads parameters and
// prompt IDs; this controller owns prefill, attention, head and decode.
module llm_soc #(parameter bit USE_QUARTUS_MEMORY = 1,
    parameter bit PERF_COUNTERS = 0,
    parameter bit ENABLE_DEBUG_INDEX = 0,
    parameter int ATTN_DIV_LANES = 4,
    parameter int SIGMOID_LANES = 4) (
    input logic clk, rst_n, host_en, host_we,
    input logic [31:0] host_addr, host_wdata,
    output logic [31:0] host_rdata,
    output logic host_ready, running, ready, error, overflow_out,
    output logic [8:0] pc_debug,
    output logic [12:0] instr_debug
);
    // Raw reset reaches only the two standard FFs in this boundary. Internal
    // state asserts reset immediately and resumes after two rising edges.
    logic core_rst_n;
    reset_release u_reset(.clk(clk), .rst_n(rst_n), .core_rst_n(core_rst_n));
    import npu_pkg::*;
    import llm_pkg::*;
    typedef enum logic [4:0] {G_IDLE, G_EMBED, G_ANORM, G_Q, G_K, G_V,
        G_RQ, G_RK, G_CACHE, G_ATTENTION, G_O, G_AADD, G_MNORM, G_GATE,
        G_UP, G_SILU, G_GMUL, G_DOWN, G_MADD, G_NEXT, G_FNORM, G_HEAD,
        G_ADVANCE, G_DONE} graph_t;
    graph_t graph;
    localparam int OP_COUNT = 112;
    localparam int O_IDLE_IDX = 0;
    localparam int O_P_REQ_IDX = 1;
    localparam int O_P_WAIT_IDX = 2;
    localparam int O_V_REQ_IDX = 3;
    localparam int O_V_WAIT_IDX = 4;
    localparam int O_K_REQ_IDX = 5;
    localparam int O_K_WAIT_IDX = 6;
    localparam int O_M_START_IDX = 7;
    localparam int O_M_WAIT_IDX = 8;
    localparam int O_WRITE_IDX = 9;
    localparam int O_FINISH_IDX = 10;
    localparam int E_SCALE_IDX = 11;
    localparam int E_DATA_IDX = 12;
    localparam int E_CALC_IDX = 13;
    localparam int E_PACK_IDX = 14;
    localparam int L_META_IDX = 15;
    localparam int L_WEIGHT_IDX = 16;
    localparam int L_INPUT_IDX = 17;
    localparam int L_MAC_IDX = 18;
    localparam int L_COEFF_IDX = 19;
    localparam int L_ROUND_IDX = 20;
    localparam int L_STORE_IDX = 21;
    localparam int N_SQUARE_IDX = 22;
    localparam int N_ACC_IDX = 23;
    localparam int N_ROOT_IDX = 24;
    localparam int N_ROOT_WAIT_IDX = 25;
    localparam int N_DIV_IDX = 26;
    localparam int N_DIV_WAIT_IDX = 27;
    localparam int N_GAIN0_IDX = 28;
    localparam int N_GAIN1_IDX = 29;
    localparam int N_INPUT_IDX = 30;
    localparam int N_RECIP_IDX = 31;
    localparam int N_GAIN_IDX = 32;
    localparam int N_PACK_IDX = 33;
    localparam int R_TABLE0_IDX = 34;
    localparam int R_TABLE1_IDX = 35;
    localparam int R_INPUT_IDX = 36;
    localparam int R_COS_IDX = 37;
    localparam int R_SIN_IDX = 38;
    localparam int R_PACK_IDX = 39;
    localparam int C_INPUT_IDX = 40;
    localparam int C_STORE_IDX = 41;
    localparam int A_QUERY_IDX = 42;
    localparam int A_KEY_IDX = 43;
    localparam int A_DOT_IDX = 44;
    localparam int A_SCALE_IDX = 45;
    localparam int A_SCORE_IDX = 46;
    localparam int A_NEXT_SCORE_IDX = 47;
    localparam int A_EXP_READ_IDX = 48;
    localparam int A_EXP_PREP_IDX = 49;
    localparam int A_EXP_MUL_IDX = 50;
    localparam int A_EXP_STORE_IDX = 51;
    localparam int A_VALUE_IDX = 52;
    localparam int A_WEIGHT_IDX = 53;
    localparam int A_ACC_IDX = 54;
    localparam int A_DIV_IDX = 55;
    localparam int A_DIV_WAIT_IDX = 56;
    localparam int A_LANE_IDX = 57;
    localparam int A_PACK_IDX = 58;
    localparam int B_INPUT0_IDX = 59;
    localparam int B_INPUT1_IDX = 60;
    localparam int B_CALC_IDX = 61;
    localparam int B_PACK_IDX = 62;
    localparam int S_INPUT_IDX = 63;
    localparam int S_SIG_IDX = 64;
    localparam int S_SIG_WAIT_IDX = 65;
    localparam int S_MUL_IDX = 66;
    localparam int S_PACK_IDX = 67;
    localparam int H_SCALE_IDX = 68;
    localparam int H_WEIGHT_IDX = 69;
    localparam int H_INPUT_IDX = 70;
    localparam int H_MAC_IDX = 71;
    localparam int H_COEFF_IDX = 72;
    localparam int H_ROUND_IDX = 73;
    localparam int H_NOISE_IDX = 74;
    localparam int H_SAMPLE_IDX = 75;
    localparam int H_SELECT_IDX = 76;
    localparam int E_ROUND_IDX = 77;
    localparam int E_CLAMP_IDX = 78;
    localparam int L_SAT_IDX = 79;
    localparam int NR_ROUND_IDX = 80;
    localparam int NR_CLAMP_IDX = 81;
    localparam int N_ROUND_IDX = 82;
    localparam int N_CLAMP_IDX = 83;
    localparam int R_ROUND_IDX = 84;
    localparam int R_CLAMP_IDX = 85;
    localparam int A_SAT_IDX = 86;
    localparam int B_ADD_CLAMP_IDX = 87;
    localparam int B_ROUND_IDX = 88;
    localparam int B_CLAMP_IDX = 89;
    localparam int S_ROUND_IDX = 90;
    localparam int S_CLAMP_IDX = 91;
    localparam int SC_MULTIPLY_IDX = 92;
    localparam int SG_CLAMP_IDX = 93;
    localparam int SG_GROUP_IDX = 94;
    localparam int SG_PICK_IDX = 95;
    localparam int SC_PAIR_IDX = 96;
    localparam int SC_SUM_IDX = 97;
    localparam int L_DECODE_IDX = 98;
    localparam int A_EXP_DELTA_IDX = 99;
    localparam int L_FLAGS_IDX = 100;
    localparam int A_FLAGS_IDX = 101;
    localparam int SC_ROUTE_IDX = 102;
    localparam int L_PRELOAD_IDX = 103;
    localparam int H_PRELOAD_IDX = 104;
    localparam int L_DOT_WAIT_IDX = 105;
    localparam int H_STREAM_WAIT_IDX = 106;
    localparam int A_STREAM_WAIT_IDX = 107;
    localparam int N_DIV_ROUND_IDX = 108;
    localparam int A_NORM_WAIT_IDX = 109;
    localparam int L_ROW_START_IDX = 110;
    localparam int L_ROW_WAIT_IDX = 111;
    typedef enum logic [OP_COUNT - 1:0] {
        O_IDLE = OP_COUNT'(1) << O_IDLE_IDX,
        O_P_REQ = OP_COUNT'(1) << O_P_REQ_IDX,
        O_P_WAIT = OP_COUNT'(1) << O_P_WAIT_IDX,
        O_V_REQ = OP_COUNT'(1) << O_V_REQ_IDX,
        O_V_WAIT = OP_COUNT'(1) << O_V_WAIT_IDX,
        O_K_REQ = OP_COUNT'(1) << O_K_REQ_IDX,
        O_K_WAIT = OP_COUNT'(1) << O_K_WAIT_IDX,
        O_M_START = OP_COUNT'(1) << O_M_START_IDX,
        O_M_WAIT = OP_COUNT'(1) << O_M_WAIT_IDX,
        O_WRITE = OP_COUNT'(1) << O_WRITE_IDX,
        O_FINISH = OP_COUNT'(1) << O_FINISH_IDX,
        E_SCALE = OP_COUNT'(1) << E_SCALE_IDX,
        E_DATA = OP_COUNT'(1) << E_DATA_IDX,
        E_CALC = OP_COUNT'(1) << E_CALC_IDX,
        E_PACK = OP_COUNT'(1) << E_PACK_IDX,
        L_META = OP_COUNT'(1) << L_META_IDX,
        L_WEIGHT = OP_COUNT'(1) << L_WEIGHT_IDX,
        L_INPUT = OP_COUNT'(1) << L_INPUT_IDX,
        L_MAC = OP_COUNT'(1) << L_MAC_IDX,
        L_COEFF = OP_COUNT'(1) << L_COEFF_IDX,
        L_ROUND = OP_COUNT'(1) << L_ROUND_IDX,
        L_STORE = OP_COUNT'(1) << L_STORE_IDX,
        N_SQUARE = OP_COUNT'(1) << N_SQUARE_IDX,
        N_ACC = OP_COUNT'(1) << N_ACC_IDX,
        N_ROOT = OP_COUNT'(1) << N_ROOT_IDX,
        N_ROOT_WAIT = OP_COUNT'(1) << N_ROOT_WAIT_IDX,
        N_DIV = OP_COUNT'(1) << N_DIV_IDX,
        N_DIV_WAIT = OP_COUNT'(1) << N_DIV_WAIT_IDX,
        N_GAIN0 = OP_COUNT'(1) << N_GAIN0_IDX,
        N_GAIN1 = OP_COUNT'(1) << N_GAIN1_IDX,
        N_INPUT = OP_COUNT'(1) << N_INPUT_IDX,
        N_RECIP = OP_COUNT'(1) << N_RECIP_IDX,
        N_GAIN = OP_COUNT'(1) << N_GAIN_IDX,
        N_PACK = OP_COUNT'(1) << N_PACK_IDX,
        R_TABLE0 = OP_COUNT'(1) << R_TABLE0_IDX,
        R_TABLE1 = OP_COUNT'(1) << R_TABLE1_IDX,
        R_INPUT = OP_COUNT'(1) << R_INPUT_IDX,
        R_COS = OP_COUNT'(1) << R_COS_IDX,
        R_SIN = OP_COUNT'(1) << R_SIN_IDX,
        R_PACK = OP_COUNT'(1) << R_PACK_IDX,
        C_INPUT = OP_COUNT'(1) << C_INPUT_IDX,
        C_STORE = OP_COUNT'(1) << C_STORE_IDX,
        A_QUERY = OP_COUNT'(1) << A_QUERY_IDX,
        A_KEY = OP_COUNT'(1) << A_KEY_IDX,
        A_DOT = OP_COUNT'(1) << A_DOT_IDX,
        A_SCALE = OP_COUNT'(1) << A_SCALE_IDX,
        A_SCORE = OP_COUNT'(1) << A_SCORE_IDX,
        A_NEXT_SCORE = OP_COUNT'(1) << A_NEXT_SCORE_IDX,
        A_EXP_READ = OP_COUNT'(1) << A_EXP_READ_IDX,
        A_EXP_PREP = OP_COUNT'(1) << A_EXP_PREP_IDX,
        A_EXP_MUL = OP_COUNT'(1) << A_EXP_MUL_IDX,
        A_EXP_STORE = OP_COUNT'(1) << A_EXP_STORE_IDX,
        A_VALUE = OP_COUNT'(1) << A_VALUE_IDX,
        A_WEIGHT = OP_COUNT'(1) << A_WEIGHT_IDX,
        A_ACC = OP_COUNT'(1) << A_ACC_IDX,
        A_DIV = OP_COUNT'(1) << A_DIV_IDX,
        A_DIV_WAIT = OP_COUNT'(1) << A_DIV_WAIT_IDX,
        A_LANE = OP_COUNT'(1) << A_LANE_IDX,
        A_PACK = OP_COUNT'(1) << A_PACK_IDX,
        B_INPUT0 = OP_COUNT'(1) << B_INPUT0_IDX,
        B_INPUT1 = OP_COUNT'(1) << B_INPUT1_IDX,
        B_CALC = OP_COUNT'(1) << B_CALC_IDX,
        B_PACK = OP_COUNT'(1) << B_PACK_IDX,
        S_INPUT = OP_COUNT'(1) << S_INPUT_IDX,
        S_SIG = OP_COUNT'(1) << S_SIG_IDX,
        S_SIG_WAIT = OP_COUNT'(1) << S_SIG_WAIT_IDX,
        S_MUL = OP_COUNT'(1) << S_MUL_IDX,
        S_PACK = OP_COUNT'(1) << S_PACK_IDX,
        H_SCALE = OP_COUNT'(1) << H_SCALE_IDX,
        H_WEIGHT = OP_COUNT'(1) << H_WEIGHT_IDX,
        H_INPUT = OP_COUNT'(1) << H_INPUT_IDX,
        H_MAC = OP_COUNT'(1) << H_MAC_IDX,
        H_COEFF = OP_COUNT'(1) << H_COEFF_IDX,
        H_ROUND = OP_COUNT'(1) << H_ROUND_IDX,
        H_NOISE = OP_COUNT'(1) << H_NOISE_IDX,
        H_SAMPLE = OP_COUNT'(1) << H_SAMPLE_IDX,
        H_SELECT = OP_COUNT'(1) << H_SELECT_IDX,
        E_ROUND = OP_COUNT'(1) << E_ROUND_IDX,
        E_CLAMP = OP_COUNT'(1) << E_CLAMP_IDX,
        L_SAT = OP_COUNT'(1) << L_SAT_IDX,
        NR_ROUND = OP_COUNT'(1) << NR_ROUND_IDX,
        NR_CLAMP = OP_COUNT'(1) << NR_CLAMP_IDX,
        N_ROUND = OP_COUNT'(1) << N_ROUND_IDX,
        N_CLAMP = OP_COUNT'(1) << N_CLAMP_IDX,
        R_ROUND = OP_COUNT'(1) << R_ROUND_IDX,
        R_CLAMP = OP_COUNT'(1) << R_CLAMP_IDX,
        A_SAT = OP_COUNT'(1) << A_SAT_IDX,
        B_ADD_CLAMP = OP_COUNT'(1) << B_ADD_CLAMP_IDX,
        B_ROUND = OP_COUNT'(1) << B_ROUND_IDX,
        B_CLAMP = OP_COUNT'(1) << B_CLAMP_IDX,
        S_ROUND = OP_COUNT'(1) << S_ROUND_IDX,
        S_CLAMP = OP_COUNT'(1) << S_CLAMP_IDX,
        SC_MULTIPLY = OP_COUNT'(1) << SC_MULTIPLY_IDX,
        SG_CLAMP = OP_COUNT'(1) << SG_CLAMP_IDX,
        SG_GROUP = OP_COUNT'(1) << SG_GROUP_IDX,
        SG_PICK = OP_COUNT'(1) << SG_PICK_IDX,
        SC_PAIR = OP_COUNT'(1) << SC_PAIR_IDX,
        SC_SUM = OP_COUNT'(1) << SC_SUM_IDX,
        L_DECODE = OP_COUNT'(1) << L_DECODE_IDX,
        A_EXP_DELTA = OP_COUNT'(1) << A_EXP_DELTA_IDX,
        L_FLAGS = OP_COUNT'(1) << L_FLAGS_IDX,
        A_FLAGS = OP_COUNT'(1) << A_FLAGS_IDX,
        L_PRELOAD = OP_COUNT'(1) << L_PRELOAD_IDX,
        H_PRELOAD = OP_COUNT'(1) << H_PRELOAD_IDX,
        L_DOT_WAIT = OP_COUNT'(1) << L_DOT_WAIT_IDX,
        H_STREAM_WAIT = OP_COUNT'(1) << H_STREAM_WAIT_IDX,
        A_STREAM_WAIT = OP_COUNT'(1) << A_STREAM_WAIT_IDX,
        N_DIV_ROUND = OP_COUNT'(1) << N_DIV_ROUND_IDX,
        A_NORM_WAIT = OP_COUNT'(1) << A_NORM_WAIT_IDX,
        L_ROW_START = OP_COUNT'(1) << L_ROW_START_IDX,
        L_ROW_WAIT = OP_COUNT'(1) << L_ROW_WAIT_IDX,
        SC_ROUTE = OP_COUNT'(1) << SC_ROUTE_IDX
    } op_t;
    op_t op;
    typedef enum logic [3:0] { RET_P_E_DATA, RET_P_E_SCALE, RET_P_H_SCALE, RET_P_H_WEIGHT, RET_P_L_META, RET_P_L_WEIGHT, RET_P_N_GAIN0, RET_P_N_GAIN1, RET_P_R_TABLE0, RET_P_R_TABLE1 } p_return_t;
    p_return_t return_p;
    typedef enum logic [3:0] { RET_V_A_QUERY, RET_V_B_INPUT0, RET_V_B_INPUT1, RET_V_C_INPUT, RET_V_H_PRELOAD, RET_V_L_PRELOAD, RET_V_N_INPUT, RET_V_N_SQUARE, RET_V_R_INPUT, RET_V_S_INPUT } v_return_t;
    v_return_t return_v;
    typedef enum logic [0:0] { RET_K_A_KEY, RET_K_A_WEIGHT } k_return_t;
    k_return_t return_k;
    typedef enum logic [3:0] { RET_M_A_ACC, RET_M_A_DOT, RET_M_B_CALC, RET_M_E_CALC, RET_M_H_MAC, RET_M_L_MAC, RET_M_N_ACC, RET_M_N_GAIN, RET_M_N_RECIP, RET_M_R_COS, RET_M_R_SIN, RET_M_S_PACK } m_return_t;
    m_return_t return_m;
    typedef enum logic [2:0] { RET_W_A_QUERY, RET_W_B_PACK, RET_W_E_PACK, RET_W_N_PACK, RET_W_O_FINISH, RET_W_O_V_REQ, RET_W_R_PACK, RET_W_L_ROW_START } w_return_t;
    w_return_t return_w;
    typedef enum logic [1:0] { RET_SCALAR_A_SCORE, RET_SCALAR_H_ROUND, RET_SCALAR_L_ROUND, RET_SCALAR_O_IDLE } scalar_return_t;
    scalar_return_t return_scalar;
    logic op_done, launch, core_running, op_fault_q;
    logic [1:0] layer_q, head_q;
    logic [6:0] position_q, time_q;
    logic [7:0] prompt_count_q, max_new_q, generated_q;
    logic [7:0] temperature_q, min_new_q;
    logic [31:0] seed_q, random_q;
    logic signed [32:0] noise_product_q;
    logic signed [63:0] sampled_score_q;
    logic [11:0] token_q, best_token_q, vocabulary_row_q;
    logic [11:0] prompt_memory [0:127], output_memory [0:127];
    logic [6:0] token_prompt_address_q;
    logic [2:0] token_prompt_bank_q;
    logic [11:0] token_prompt_word_q [0:7], token_feedback_q;
    logic token_feedback_source_q;
    logic token_read_valid_q, token_commit_valid_q, token_valid_q;
    logic [3:0] row_q, chunk_q;
    logic [4:0] lane_q;
    logic [2:0] source_q, destination_q;
    logic [9:0] matrix_row_q, matrix_rows_q;
    logic [3:0] matrix_chunks_q;
    logic [14:0] weight_row_q;
    logic [23:0] coefficient_q;
    logic [255:0] parameter_word_q;
    // One portable operand cache is shared by mutually exclusive linear/head operations.
    logic [767:0] input_cache_q [0:11];
    logic input_cache_valid_q, input_cache_gate_q;
    logic [2:0] input_cache_source_q;
    logic [3:0] input_cache_chunks_q;
    logic [3:0] preload_chunk_q;
    logic rope_table_valid_q;
    logic [6:0] rope_table_position_q;
    logic [255:0] head_scale_word_q;
    logic [511:0] table_q;
    logic [767:0] vector_q, second_q, cache_operand_q, write_vector_q, query_q;
    logic [6:0] write_vector_addr_q;
    logic [31:0] write_vector_mask_q;
    logic signed [38:0] linear_acc_q;
    logic signed [63:0] scalar_product_q, scalar_round_q;
    logic signed [38:0] scalar_a_q;
    logic signed [24:0] scalar_b_q;
    logic signed [47:0] scalar_partial_q [0:2];
    wire [47:0] scalar_partial_comb [0:2];
    logic_mul #(.A_W(39), .B_W(8), .OUT_W(48), .SIGNED_A(1), .SIGNED_B(0)) u_scalar_lo
        (.a(scalar_a_q), .b(scalar_b_q[7:0]), .product(scalar_partial_comb[0]));
    logic_mul #(.A_W(39), .B_W(8), .OUT_W(48), .SIGNED_A(1), .SIGNED_B(0)) u_scalar_mid
        (.a(scalar_a_q), .b(scalar_b_q[15:8]), .product(scalar_partial_comb[1]));
    logic_mul #(.A_W(39), .B_W(9), .OUT_W(48), .SIGNED_A(1), .SIGNED_B(1)) u_scalar_hi
        (.a(scalar_a_q), .b(scalar_b_q[24:16]), .product(scalar_partial_comb[2]));

    logic signed [55:0] scalar_pair_q;
    logic signed [23:0] scalar_group_q [0:7];
    logic signed [23:0] scalar_packet_low_q;
    logic scalar_packet_high_q, scalar_packet_lower_q, scalar_packet_linear_q;
    logic [2:0] scalar_packet_group_q;
    logic scalar_packet_valid_q;
    logic signed [23:0] scalar_cluster_low_q [0:1];
    logic [1:0] scalar_cluster_high_q, scalar_cluster_lower_q, scalar_cluster_valid_q;
    logic [1:0] scalar_cluster_group_q [0:1];
    logic signed [63:0] lane_raw_q [0:31], lane_round_q [0:31];
    logic [7:0] round16_group_q;
    logic [63:0] square_sum_q, root_input_q;
    // epsilon >=42950 makes root>=207, so rounded 2^32/root fits U25.
    // Avoid distributing seven redundant sign/zero bits across all SIMD lanes.
    logic [24:0] reciprocal_q;
    logic signed [55:0] rotation_cos_q [0:31];
    logic signed [55:0] attention_acc_q [0:31];
    logic signed [31:0] max_score_q, best_score_q;
    logic [24:0] exp_hi_q, exp_lo_q, probability_q;
    logic [31:0] probability_sum_q;
    logic [32:0] exp_difference_q;
    logic [36:0] exp_interpolation_q;
    logic [24:0] exp_delta_q;
    wire [36:0] exp_interpolation_comb;
    logic_mul #(.A_W(25), .B_W(12), .OUT_W(37), .SIGNED_A(0), .SIGNED_B(0)) u_exp_mul
        (.a(exp_delta_q), .b(exp_difference_q[11:0]), .product(exp_interpolation_comb));
    wire signed [23:0] gumbel_value;
    wire [32:0] noise_product_comb;
    logic_mul #(.A_W(24), .B_W(8), .OUT_W(33), .SIGNED_A(1), .SIGNED_B(0)) u_noise_mul
        (.a(gumbel_value), .b(temperature_q), .product(noise_product_comb));

    wire [24:0] exp_value_hi, exp_value_lo;
    llm_gumbel_sample u_gumbel_lookup(.index(random_q[31:24]), .value(gumbel_value));
    llm_exp_sample u_exp_hi(.index({1'b0, exp_difference_q[19:12]}), .value(exp_value_hi));
    llm_exp_sample u_exp_lo(.index({1'b0, exp_difference_q[19:12]} + 9'd1), .value(exp_value_lo));

    logic divide_negative_q;

    wire [6:0] op_debug_index;
    wire [OP_COUNT:0] op_debug_prefix [0:6];
    genvar debug_bit, debug_state;
    generate
    if (ENABLE_DEBUG_INDEX) begin : g_debug_enabled
    for (debug_bit = 0; debug_bit < 7; debug_bit = debug_bit + 1) begin : g_debug_bit
        assign op_debug_prefix[debug_bit][0] = 1'b0;
        for (debug_state = 0; debug_state < OP_COUNT; debug_state = debug_state + 1) begin : g_state
            assign op_debug_prefix[debug_bit][debug_state + 1] =
                op_debug_prefix[debug_bit][debug_state] | (op[debug_state] && ((debug_state >> debug_bit) & 1));
        end
        assign op_debug_index[debug_bit] = op_debug_prefix[debug_bit][OP_COUNT];
    end
    end else begin : g_debug_disabled
        assign op_debug_index = 7'd0;
    end
    endgenerate

    // Registered host transactions. Hold address/data until ready, then deassert
    // host_en for at least one clock before issuing another transaction.
    typedef enum logic [2:0] {H_IDLE, H_EXEC, H_READ, H_WAIT, H_DONE} host_t;
    host_t host_state;
    logic [31:0] host_payload_q;
    logic [31:0] host_address_q, host_data_q;
    logic host_write_q, host_parameter_q;
    logic [14:0] p_address_q;
    logic p_read, p_valid, p_host_valid;
    logic linear_parameter_req, linear_ready, linear_busy, linear_done, linear_fault, linear_dot_issue;
    logic [14:0] linear_parameter_address;
    logic [3:0] linear_input_chunk;
    logic signed [38:0] linear_dot_acc;
    wire signed [23:0] linear_operand [0:31];
    logic head_parameter_req, head_capture, head_math_issue, head_dot_done;
    logic [14:0] head_parameter_address;
    logic [1:0] head_input_chunk;
    logic signed [38:0] head_dot_acc;
    logic attention_k_req, attention_capture, attention_math_issue, attention_scores_done;
    logic [11:0] attention_k_address;
    logic signed [31:0] attention_score, attention_max;
    logic [255:0] p_data;
    logic [31:0] p_host_data;
    llm_parameter_ram #(.ADDR_W(15), .DEPTH(PARAM_ROWS),
        .USE_QUARTUS_MEMORY(USE_QUARTUS_MEMORY)) u_parameters(
        .clk(clk), .rst_n(core_rst_n), .rd_en(p_read), .rd_addr(linear_parameter_req ? linear_parameter_address :
            head_parameter_req ? head_parameter_address : p_address_q),
        .rd_data(p_data), .rd_valid(p_valid),
        .host_active(host_en && !core_running && host_parameter_q),
        .host_write_req(host_en && !core_running && host_parameter_q &&
            host_state == H_EXEC && host_write_q),
        .host_read_req(host_en && !core_running && host_parameter_q &&
            host_state == H_READ && !host_write_q),
        .host_we(host_write_q), .host_addr(host_address_q[19:2]),
        .host_wdata(host_data_q), .host_rdata(p_host_data), .host_rvalid(p_host_valid));
    assign p_read = op[O_P_REQ_IDX] || head_parameter_req || linear_parameter_req;
    always_ff @(posedge clk or negedge core_rst_n) begin
        if (!core_rst_n) begin
            host_state <= H_IDLE;
            host_ready <= 0;
            host_payload_q <= 0;
            launch <= 0;
            prompt_count_q <= 0;
            max_new_q <= 96;
            temperature_q <= 166;
            min_new_q <= 64;
            seed_q <= 32'd1;
            host_parameter_q <= 0;
            host_write_q <= 0;
            host_address_q <= 0;
            host_data_q <= 0;
        end else begin
            launch <= 0;
            if (!host_en) begin host_state <= H_IDLE; host_ready <= 0; end
            else case (host_state)
                H_IDLE : begin
                    host_address_q <= host_addr;
                    host_data_q <= host_wdata;
                    host_write_q <= host_we;
                    host_parameter_q <= host_addr < 32'h000c0000 && host_addr[1:0] == 0;
                    host_state <= H_EXEC;
                end
                H_EXEC : begin
                    host_payload_q <= 0;
                    if (host_address_q[1:0] != 0) host_state <= H_DONE;
                    else if (host_write_q) begin
                        if (!core_running) begin
                            if (host_address_q[31:9] == 23'h800)
                                prompt_memory[host_address_q[8:2]] <= host_data_q[11:0];
                            if (host_address_q[31:5] == 27'h0020000)
                                case (host_address_q[4:2])
                                    3'd1 : prompt_count_q <= host_data_q[7:0];
                                    3'd2 : max_new_q <= host_data_q[7:0];
                                    3'd3 : launch <= host_data_q[0];
                                    3'd4 : temperature_q <= host_data_q[7:0];
                                    3'd5 : seed_q <= host_data_q == 0 ? 32'd1 : host_data_q;
                                    3'd6 : min_new_q <= host_data_q[7:0];
                                    default : ;
                                endcase
                        end
                        host_state <= host_parameter_q && !core_running ? H_WAIT : H_DONE;
                    end else if (host_parameter_q && !core_running) host_state <= H_READ;
                    else begin
                        if (host_address_q == 32'h00400000)
                            host_payload_q <= {20'h0, generated_q, overflow_out, error, ready, running};
                        else if (host_address_q[31:9] == 23'h1000 && !core_running)
                            host_payload_q <= {20'h0, output_memory[host_address_q[8:2]]};
                        host_state <= H_DONE;
                    end
                end
                H_READ : host_state <= H_WAIT;
                H_WAIT : if (p_host_valid) begin
                    if (!host_write_q) host_payload_q <= p_host_data;
                    host_state <= H_DONE;
                end
                H_DONE : host_ready <= 1;
                default : host_state <= H_IDLE;
            endcase
        end
    end

    // H_DONE already follows payload capture. This unconditional public
    // register has valid data on the same edge as host_ready, with a simple D
    // input rather than simultaneous synchronous clear/load output controls.
    always_ff @(posedge clk or negedge core_rst_n)
        if (!core_rst_n) host_rdata <= 0;
        else host_rdata <= host_payload_q;

    logic v_read, v_valid, v_write_busy;
    logic [6:0] v_address_q;
    logic [767:0] v_data;
    llm_bank_ram #(.ROWS(96), .ADDR_W(7), .USE_QUARTUS_MEMORY(USE_QUARTUS_MEMORY)) u_vectors(
        .clk(clk), .rst_n(core_rst_n), .rd_en(v_read), .rd_addr(v_address_q),
        .rd_data(v_data), .rd_valid(v_valid), .wr_busy(v_write_busy), .wr_addr(write_vector_addr_q),
        .wr_mask(op[O_WRITE_IDX] ? write_vector_mask_q : 32'h0), .wr_data(write_vector_q));
    assign v_read = op[O_V_REQ_IDX];
    logic k_read, k_valid, k_write_busy;
    logic [11:0] k_address_q, k_write_address_q;
    logic [767:0] k_data;
    wire [11:0] k_read_address = attention_k_req ? attention_k_address : k_address_q;
    // Address = layer*1024 + position*8 + K/V*4 + head.
    llm_bank_ram #(.USE_QUARTUS_MEMORY(USE_QUARTUS_MEMORY)) u_cache(
        .clk(clk), .rst_n(core_rst_n), .rd_en(k_read), .rd_addr(k_read_address),
        .rd_data(k_data), .rd_valid(k_valid), .wr_busy(k_write_busy), .wr_addr(k_write_address_q),
        .wr_mask(op[C_STORE_IDX] ? 32'hffffffff : 32'h0), .wr_data(vector_q));
    assign k_read = op[O_K_REQ_IDX] || attention_k_req;

    logic math_start, math_busy, math_done, math_in_ready, math_product_valid, math_sum_valid;
    logic signed [23:0] math_a_q [0:31];
    logic signed [31:0] math_b_q [0:31];
    logic signed [55:0] math_product [0:31];
    logic signed [60:0] math_sum;
    llm_math #(.STREAMING(1)) u_math(.clk(clk), .rst_n(core_rst_n), .start(math_start),
        .a(math_a_q), .b(math_b_q), .busy(math_busy), .done(math_done),
        .product(math_product), .sum(math_sum), .in_ready(math_in_ready),
        .product_valid(math_product_valid), .sum_valid(math_sum_valid));
    assign math_start = op[O_M_START_IDX] || head_math_issue || attention_math_issue;
    llm_head_engine u_head_engine(.clk(clk), .rst_n(core_rst_n), .start_i(op[H_SCALE_IDX]),
        .cancel_i(op_fault_q), .vocabulary_i(vocabulary_row_q),
        .parameter_req_o(head_parameter_req), .parameter_address_o(head_parameter_address),
        .parameter_valid_i(p_valid), .operand_capture_o(head_capture), .math_issue_o(head_math_issue),
        .input_chunk_o(head_input_chunk), .sum_valid_i(math_sum_valid), .sum_i(math_sum),
        .done_o(head_dot_done), .accumulator_o(head_dot_acc));
    llm_attention_engine u_attention_engine(.clk(clk), .rst_n(core_rst_n), .start_i(op[A_QUERY_IDX]),
        .cancel_i(op_fault_q), .layer_i(layer_q), .head_i(head_q), .position_i(position_q),
        .kv_req_o(attention_k_req), .kv_address_o(attention_k_address), .kv_valid_i(k_valid),
        .operand_capture_o(attention_capture), .math_issue_o(attention_math_issue),
        .sum_valid_i(math_sum_valid), .sum_i(math_sum), .score_address_i(time_q),
        .score_o(attention_score), .max_score_o(attention_max), .done_o(attention_scores_done));
    generate
    for (genvar input_lane = 0; input_lane < 32; input_lane = input_lane + 1) begin : g_linear_operand
        assign linear_operand[input_lane] = input_cache_q[linear_input_chunk][input_lane * 24 +: 24];
    end
    endgenerate
    llm_linear_engine u_linear_engine(.clk(clk), .rst_n(core_rst_n), .start_i(op[L_ROW_START_IDX]),
        .cancel_i(op_fault_q), .weight_base_i(weight_row_q), .chunks_i(matrix_chunks_q),
        .ready_o(linear_ready), .busy_o(linear_busy), .done_o(linear_done), .fault_o(linear_fault),
        .parameter_req_o(linear_parameter_req), .parameter_address_o(linear_parameter_address),
        .parameter_valid_i(p_valid), .parameter_data_i(p_data), .input_chunk_o(linear_input_chunk),
        .x_i(linear_operand), .dot_issue_o(linear_dot_issue), .accumulator_o(linear_dot_acc));
    logic root_busy, root_done;
    logic [31:0] root;
    isqrt_u64 u_root(.clk(clk), .rst_n(core_rst_n), .start(op[N_ROOT_IDX]),
        .radicand(root_input_q), .busy(root_busy), .done(root_done), .root(root));
    logic div_busy, div_done, div_zero;
    logic [63:0] div_numerator_q, div_quotient;
    logic [31:0] div_denominator_q, div_remainder;
    logic [32:0] twice_remainder;
    logic divide_round_up;
    logic [24:0] norm_quotient_q;
    logic norm_round_q;
    logic attention_norm_ready, attention_norm_done, attention_div_start;
    logic [767:0] attention_normalized;
    wire [63:0] attention_div_numerator;
    wire [31:0] attention_div_denominator;
    llm_attention_normalize #(.DIV_LANES(ATTN_DIV_LANES), .USE_SHARED(1)) u_attention_normalize(
        .clk(clk), .rst_n(core_rst_n), .start_i(op[A_LANE_IDX]), .cancel_i(op_fault_q),
        .accumulator_i(attention_acc_q), .denominator_i(probability_sum_q),
        .shared_busy_i(div_busy), .shared_done_i(div_done), .shared_quotient_i(div_quotient),
        .shared_remainder_i(div_remainder), .shared_numerator_o(attention_div_numerator),
        .shared_denominator_o(attention_div_denominator),
        .ready_o(attention_norm_ready), .batch_start_o(attention_div_start),
        .done_o(attention_norm_done), .vector_o(attention_normalized));
    div #(.NUM_W(64), .DEN_W(32)) u_div(.clk(clk), .rst_n(core_rst_n),
        .start(op[N_DIV_IDX] || attention_div_start),
        .numerator(attention_div_start ? attention_div_numerator : div_numerator_q),
        .denominator(attention_div_start ? attention_div_denominator : div_denominator_q), .busy(div_busy), .done(div_done),
        .div_zero(div_zero), .quotient(div_quotient), .remainder(div_remainder));
    assign twice_remainder = {div_remainder, 1'b0};
    assign divide_round_up = twice_remainder > {1'b0, div_denominator_q} ||
        (twice_remainder == {1'b0, div_denominator_q} && div_quotient[0]);
    localparam int SIGMOID_SHIFT = $clog2(SIGMOID_LANES);
    logic [SIGMOID_LANES - 1:0] sig_busy, sig_done;
    logic signed [15:0] sig_x_q [0:SIGMOID_LANES - 1];
    logic signed [15:0] sigmoid_inputs_q [0:31];
    logic [15:0] sig_y [0:SIGMOID_LANES - 1];
    logic [15:0] sigmoid_values_q [0:31];
    generate
    for (genvar sig_lane = 0; sig_lane < SIGMOID_LANES; sig_lane = sig_lane + 1) begin : g_sigmoid
        sigmoid u_sig(.clk(clk), .rst_n(core_rst_n), .start(op[S_SIG_IDX]),
            .x_raw(sig_x_q[sig_lane]), .frac_bits(5'd12), .busy(sig_busy[sig_lane]),
            .done(sig_done[sig_lane]), .y_raw(sig_y[sig_lane]));
        always_ff @(posedge clk)
            if (core_rst_n && op[SG_GROUP_IDX]) sig_x_q[sig_lane] <= sigmoid_inputs_q[int'(lane_q) + sig_lane];
    end
    endgenerate
    assign core_running = graph != G_IDLE;
    generate
    if (PERF_COUNTERS) begin : g_perf
        logic [63:0] total_cycles, parameter_reads, vector_reads, vector_writes;
        logic [63:0] kv_reads, kv_writes, math_starts, divider_starts, sigmoid_starts;
        logic [63:0] graph_cycles [0:23];
        always_ff @(posedge clk or negedge core_rst_n) begin
            if (!core_rst_n) begin
                total_cycles <= 0; parameter_reads <= 0; vector_reads <= 0; vector_writes <= 0;
                kv_reads <= 0; kv_writes <= 0; math_starts <= 0; divider_starts <= 0; sigmoid_starts <= 0;
            end else if (launch && graph == G_IDLE) begin
                total_cycles <= 0; parameter_reads <= 0; vector_reads <= 0; vector_writes <= 0;
                kv_reads <= 0; kv_writes <= 0; math_starts <= 0; divider_starts <= 0; sigmoid_starts <= 0;
            end else if (core_running) begin
                total_cycles <= total_cycles + 1'b1;
                if (p_read) parameter_reads <= parameter_reads + 1'b1;
                if (v_read) vector_reads <= vector_reads + 1'b1;
                if (op[O_WRITE_IDX] && |write_vector_mask_q) vector_writes <= vector_writes + 1'b1;
                if (k_read) kv_reads <= kv_reads + 1'b1;
                if (op[C_STORE_IDX]) kv_writes <= kv_writes + 1'b1;
                if (math_start) math_starts <= math_starts + 1'b1;
                if (attention_div_start) divider_starts <= divider_starts + 64'(ATTN_DIV_LANES);
                else if (op[N_DIV_IDX]) divider_starts <= divider_starts + 1'b1;
                if (op[S_SIG_IDX]) sigmoid_starts <= sigmoid_starts + 64'(SIGMOID_LANES);
            end
        end
        for (genvar phase = 0; phase < 24; phase = phase + 1) begin : g_phase
            always_ff @(posedge clk or negedge core_rst_n)
                if (!core_rst_n) graph_cycles[phase] <= 0;
                else if (launch && graph == G_IDLE) graph_cycles[phase] <= 0;
                else if (core_running && graph == graph_t'(phase))
                    graph_cycles[phase] <= graph_cycles[phase] + 1'b1;
        end
    end
    endgenerate
    always_ff @(posedge clk or negedge core_rst_n) begin
        if (!core_rst_n) begin running <= 0; ready <= 1; pc_debug <= 0; instr_debug <= 0; end
        else begin
            running <= core_running; ready <= !core_running;
            pc_debug <= {2'b0, position_q}; instr_debug <= {1'b0, graph, op_debug_index};
        end
    end

    function automatic logic [14:0] matrix_meta(input logic [1:0] layer_id, input logic [2:0] matrix_id);
        matrix_meta = 15'(MATRIX_META_BASE + ((int'(layer_id) << 3) - int'(layer_id)) + matrix_id);
    endfunction
    function automatic logic [14:0] gain_address(input graph_t phase, input logic [1:0] layer_id,
                                                input logic [3:0] row_id);
        if (phase == G_FNORM) gain_address = 15'(GAIN_BASE + 64 + (int'(row_id) << 1));
        else gain_address = 15'(GAIN_BASE + (int'(layer_id) << 4) + (phase == G_MNORM ? 8 : 0) + (int'(row_id) << 1));
    endfunction

    always_ff @(posedge clk or negedge core_rst_n) begin
        if (!core_rst_n) begin
            graph <= G_IDLE; layer_q <= 0; position_q <= 0; generated_q <= 0;
            error <= 0;
        end else begin
            if (graph == G_IDLE && launch) begin
                error <= 0; layer_q <= 0; position_q <= 0; generated_q <= 0;
                if (prompt_count_q == 0 || max_new_q == 0 ||
                    {1'b0, prompt_count_q} + {1'b0, max_new_q} > 128) error <= 1;
                else graph <= G_EMBED;
            end else if (op_fault_q && core_running && graph != G_DONE) begin graph <= G_DONE; error <= 1; end
            else if (op_done) begin
                case (graph)
                    G_EMBED : graph <= G_ANORM;
                    G_ANORM : graph <= G_Q;
                    G_Q : graph <= G_K;
                    G_K : graph <= G_V;
                    G_V : graph <= G_RQ;
                    G_RQ : graph <= G_RK;
                    G_RK : graph <= G_CACHE;
                    G_CACHE : graph <= G_ATTENTION;
                    G_ATTENTION : graph <= G_O;
                    G_O : graph <= G_AADD;
                    G_AADD : graph <= G_MNORM;
                    G_MNORM : graph <= G_GATE;
                    G_GATE : graph <= G_UP;
                    G_UP : graph <= G_SILU;
                    G_SILU : graph <= G_GMUL;
                    G_GMUL : graph <= G_DOWN;
                    G_DOWN : graph <= G_MADD;
                    G_MADD : graph <= G_NEXT;
                    G_FNORM : graph <= G_HEAD;
                    G_HEAD : graph <= G_ADVANCE;
                    default : ;
                endcase
            end else case (graph)
                G_NEXT : begin
                    if (layer_q != 3) begin layer_q <= layer_q + 1'b1; graph <= G_ANORM; end
                    else if ({1'b0, position_q} + 1 < prompt_count_q) begin
                        position_q <= position_q + 1'b1;
                        layer_q <= 0; graph <= G_EMBED;
                    end else graph <= G_FNORM;
                end
                G_ADVANCE : begin
                    output_memory[generated_q[6:0]] <= best_token_q;
                    generated_q <= generated_q + 1'b1;
                    if (generated_q + 1 >= max_new_q || best_token_q == 12'd1 || position_q == 127)
                        graph <= G_DONE;
                    else begin
                        position_q <= position_q + 1'b1;
                        layer_q <= 0; graph <= G_EMBED;
                    end
                end
                G_DONE : graph <= G_IDLE;
                default : ;
            endcase
        end
    end

    // Graph decisions only capture a token request. Local prompt selection and
    // token commit occupy separate edges; G_EMBED waits for token validity.
    wire token_launch_request = graph == G_IDLE && launch && prompt_count_q != 0 &&
        max_new_q != 0 && {1'b0, prompt_count_q} + {1'b0, max_new_q} <= 128;
    wire token_prefill_request = graph == G_NEXT && !op_fault_q && !op_done &&
        layer_q == 3 && {1'b0, position_q} + 1 < prompt_count_q;
    wire token_decode_request = graph == G_ADVANCE && !op_fault_q && !op_done &&
        generated_q + 1 < max_new_q && best_token_q != 12'd1 && position_q != 127;
    wire token_request = token_launch_request || token_prefill_request || token_decode_request;
    wire token_abort = op_fault_q && core_running && graph != G_DONE;
    wire token_consume = op[O_IDLE_IDX] && !op_done && graph == G_EMBED && token_valid_q;
    always_ff @(posedge clk or negedge core_rst_n) begin
        if (!core_rst_n) begin
            token_read_valid_q <= 0; token_commit_valid_q <= 0; token_valid_q <= 0;
        end else if (token_abort) begin
            token_read_valid_q <= 0; token_commit_valid_q <= 0; token_valid_q <= 0;
        end else begin
            token_read_valid_q <= token_request;
            token_commit_valid_q <= token_read_valid_q;
            if (token_request || token_consume) token_valid_q <= 0;
            else if (token_commit_valid_q) token_valid_q <= 1;
        end
    end
    always_ff @(posedge clk)
        if (core_rst_n && token_request) begin
            token_prompt_address_q <= token_prefill_request ? position_q + 1'b1 : 7'd0;
            token_feedback_source_q <= token_decode_request;
            if (token_decode_request) token_feedback_q <= best_token_q;
        end
    always_ff @(posedge clk)
        if (core_rst_n && !token_abort && token_read_valid_q)
            token_prompt_bank_q <= token_prompt_address_q[6:4];
    genvar prompt_bank;
    generate
    for (prompt_bank = 0; prompt_bank < 8; prompt_bank = prompt_bank + 1) begin : g_prompt_read
        always_ff @(posedge clk)
            if (core_rst_n && !token_abort && token_read_valid_q)
                token_prompt_word_q[prompt_bank] <= prompt_memory[{3'(prompt_bank), token_prompt_address_q[3:0]}];
    end
    endgenerate
    always_ff @(posedge clk or negedge core_rst_n)
        if (!core_rst_n) token_q <= 0;
        else if (!token_abort && token_commit_valid_q)
            token_q <= token_feedback_source_q ? token_feedback_q : token_prompt_word_q[token_prompt_bank_q];

    // Independent lane registers keep constant slice boundaries visible to
    // synthesis. The FSM carries enables and addresses, while each lane owns
    // its arithmetic payload and its portion of the workspace write bus.
    // The wide scalar result is reduced only after full-width clamp decisions.
    // Two registered clusters bound the distribution to four output groups.
    always_ff @(posedge clk or negedge core_rst_n)
        if (!core_rst_n) scalar_packet_valid_q <= 0;
        else scalar_packet_valid_q <= op[L_FLAGS_IDX] || op[A_FLAGS_IDX];
    always_ff @(posedge clk)
        if (core_rst_n && (op[L_FLAGS_IDX] || op[A_FLAGS_IDX])) begin
            scalar_packet_low_q <= scalar_round_q[23:0];
            scalar_packet_high_q <= scalar_round_q > 64'sd8388607;
            scalar_packet_lower_q <= scalar_round_q < -64'sd8388608;
            scalar_packet_group_q <= op[L_FLAGS_IDX] ? matrix_row_q[4:2] : lane_q[4:2];
            scalar_packet_linear_q <= op[L_FLAGS_IDX];
        end
    genvar lane, scalar_group, scalar_cluster, round_group;
    generate
    // Prepare each four-lane enable on the existing raw-product capture edge.
    for (round_group = 0; round_group < 8; round_group = round_group + 1) begin : g_round_control
        always_ff @(posedge clk or negedge core_rst_n)
            if (!core_rst_n) round16_group_q[round_group] <= 0;
            else round16_group_q[round_group] <= op[N_RECIP_IDX] || op[B_CALC_IDX];
    end
    for (lane = 0; lane < 32; lane = lane + 1) begin : g_simd
        // Cache payload is held by the RAM response until the next read.
        // A_KEY/A_WEIGHT follow O_K_WAIT with k_valid, so this plain FF
        // has captured the accepted response before either consumes it.
        // Binary vector operations own second_q independently.
        always_ff @(posedge clk)
            cache_operand_q[lane * 24 +: 24] <= k_data[lane * 24 +: 24];
        always_ff @(posedge clk) begin
            if (core_rst_n) begin
                if (head_capture) math_a_q[lane] <= input_cache_q[{2'b0, head_input_chunk}][lane * 24 +: 24];
                else if (attention_capture) math_a_q[lane] <= query_q[lane * 24 +: 24];
                else unique case (1'b1)
                    op[E_DATA_IDX] : math_a_q[lane] <= 24'($signed(parameter_word_q[lane * 8 +: 8]));
                    op[N_SQUARE_IDX], op[N_INPUT_IDX], op[R_INPUT_IDX],
                    op[S_MUL_IDX] : math_a_q[lane] <= vector_q[lane * 24 +: 24];
                    op[NR_CLAMP_IDX] : math_a_q[lane] <= llm_sat24(lane_round_q[lane]);
                    op[R_COS_IDX] : math_a_q[lane] <= vector_q[((lane + 16) % 32) * 24 +: 24];
                    op[A_EXP_READ_IDX] : begin
                    exp_difference_q <= 33'(max_score_q) - 33'(attention_score); op <= A_EXP_PREP;
                end
                op[A_EXP_PREP_IDX] : begin
                    if (exp_difference_q >= 33'd1048576) begin exp_hi_q <= 0; exp_lo_q <= 0; end
                    else begin
                        exp_hi_q <= exp_value_hi;
                        exp_lo_q <= exp_value_lo;
                    end
                    op <= A_EXP_DELTA;
                end
                op[A_EXP_DELTA_IDX] : begin exp_delta_q <= exp_hi_q - exp_lo_q; op <= A_EXP_MUL; end
                op[A_EXP_MUL_IDX] : begin
                    exp_interpolation_q <= exp_interpolation_comb; op <= A_EXP_STORE;
                end
                op[A_EXP_STORE_IDX] : begin
                    probability_q <= exp_hi_q - 25'((exp_interpolation_q + 37'd2048) >> 12);
                    probability_sum_q <= probability_sum_q + exp_hi_q - 32'((exp_interpolation_q + 37'd2048) >> 12);
                    k_address_q <= {layer_q, time_q, 1'b1, head_q}; return_k <= RET_K_A_WEIGHT; op <= O_K_REQ;
                end
                op[A_WEIGHT_IDX] : begin
                    begin return_m <= RET_M_A_ACC; op <= O_M_START; end
                end
                op[A_ACC_IDX] : begin
                    if (time_q == position_q) begin lane_q <= 0; op <= A_LANE; end
                    else begin time_q <= time_q + 1'b1; op <= A_EXP_READ; end
                end
                op[A_LANE_IDX] : if (attention_norm_ready) op <= A_NORM_WAIT;
                op[A_NORM_WAIT_IDX] : if (attention_norm_done) begin
                    write_vector_addr_q <= 7'(60 + head_q); write_vector_mask_q <= 32'hffffffff; op <= O_WRITE;
                    if (head_q == 3) return_w <= RET_W_O_FINISH;
                    else begin
                        head_q <= head_q + 1'b1; time_q <= 0;
                        max_score_q <= 32'sh80000000; probability_sum_q <= 0;
                        v_address_q <= 7'(24 + head_q + 1'b1); return_v <= RET_V_A_QUERY; return_w <= RET_W_O_V_REQ;
                    end
                end
                op[A_FLAGS_IDX] : op <= SC_ROUTE;
                op[A_SAT_IDX] : op <= A_PACK;
                op[A_PACK_IDX] : begin
                    if (lane_q == 31) begin write_vector_addr_q <= 7'(((int'($unsigned(3'(5))) << 3) + (int'($unsigned(3'(5))) << 2)) + int'($unsigned(4'({2'b0, head_q})))); write_vector_mask_q <= 32'hffffffff; return_w <= RET_W_A_QUERY; op <= O_WRITE; end
                    else begin lane_q <= lane_q + 1'b1; op <= A_LANE; end
                    if (lane_q == 31) begin
                        if (head_q == 3) return_w <= RET_W_O_FINISH;
                        else begin
                            head_q <= head_q + 1'b1; time_q <= 0;
                            max_score_q <= 32'sh80000000; probability_sum_q <= 0;
                            v_address_q <= 7'(2 * 12 + head_q + 1); return_v <= RET_V_A_QUERY; return_w <= RET_W_O_V_REQ;
                        end
                    end
                end
                op[B_INPUT0_IDX] : begin
                    begin v_address_q <= 7'(((int'($unsigned(3'(graph == G_GMUL ? 3'd7 : 3'd1))) << 3) + (int'($unsigned(3'(graph == G_GMUL ? 3'd7 : 3'd1))) << 2)) + int'($unsigned(4'(row_q)))); return_v <= RET_V_B_INPUT1; op <= O_V_REQ; end
                end
                op[B_INPUT1_IDX] : begin
                    if (graph == G_GMUL) begin
                        begin return_m <= RET_M_B_CALC; op <= O_M_START; end
                    end else op <= B_ADD_CLAMP;
                end
                op[B_ADD_CLAMP_IDX] : begin write_vector_addr_q <= 7'(((int'($unsigned(3'(0))) << 3) + (int'($unsigned(3'(0))) << 2)) + int'($unsigned(4'(row_q)))); write_vector_mask_q <= 32'hffffffff; return_w <= RET_W_B_PACK; op <= O_WRITE; end
                op[B_CALC_IDX] : op <= B_ROUND;
                op[B_ROUND_IDX] : op <= B_CLAMP;
                op[B_CLAMP_IDX] : begin
                    begin write_vector_addr_q <= 7'(((int'($unsigned(3'(6))) << 3) + (int'($unsigned(3'(6))) << 2)) + int'($unsigned(4'(row_q)))); write_vector_mask_q <= 32'hffffffff; return_w <= RET_W_B_PACK; op <= O_WRITE; end
                end
                op[B_PACK_IDX] : if (row_q == (graph == G_GMUL ? 11 : 3)) op <= O_FINISH;
                    else begin row_q <= row_q + 1'b1; begin v_address_q <= 7'(((int'($unsigned(3'(graph == G_GMUL ? 3'd6 : 3'd0))) << 3) + (int'($unsigned(3'(graph == G_GMUL ? 3'd6 : 3'd0))) << 2)) + int'($unsigned(4'(row_q + 1'b1)))); return_v <= RET_V_B_INPUT0; op <= O_V_REQ; end end
                op[S_INPUT_IDX] : begin lane_q <= 0; op <= SG_CLAMP; end
                op[SG_CLAMP_IDX] : op <= SG_GROUP;
                op[SG_GROUP_IDX] : op <= SG_PICK;
                op[SG_PICK_IDX] : op <= S_SIG;
                op[S_SIG_IDX] : op <= S_SIG_WAIT;
                op[S_SIG_WAIT_IDX] : if (&sig_done) begin
                    if (int'(lane_q) + SIGMOID_LANES >= 32) begin lane_q <= 0; op <= S_MUL; end
                    else begin
                        lane_q <= lane_q + 5'(SIGMOID_LANES);
                        op <= SG_GROUP;
                    end
                end
                op[S_MUL_IDX] : begin
                    begin return_m <= RET_M_S_PACK; op <= O_M_START; end
                end
                op[S_PACK_IDX] : op <= S_ROUND;
                op[S_ROUND_IDX] : op <= S_CLAMP;
                op[S_CLAMP_IDX] : begin
                    begin write_vector_addr_q <= 7'(((int'($unsigned(3'(6))) << 3) + (int'($unsigned(3'(6))) << 2)) + int'($unsigned(4'(row_q)))); write_vector_mask_q <= 32'hffffffff; return_w <= RET_W_B_PACK; op <= O_WRITE; end
                    if (row_q == 11) return_w <= RET_W_O_FINISH;
                    else begin row_q <= row_q + 1'b1; v_address_q <= 7'(6 * 12 + row_q + 1); return_v <= RET_V_S_INPUT; return_w <= RET_W_O_V_REQ; end
                end
                op[H_PRELOAD_IDX] : begin
                    if (preload_chunk_q == 3) begin
                        p_address_q <= 15'(EMB_SCALE_BASE); return_p <= RET_P_H_SCALE; op <= O_P_REQ;
                    end else begin
                        preload_chunk_q <= preload_chunk_q + 1'b1;
                        v_address_q <= 7'(12 + preload_chunk_q + 1); return_v <= RET_V_H_PRELOAD; op <= O_V_REQ;
                    end
                end
                op[H_SCALE_IDX] : begin
                    if (vocabulary_row_q[2:0] == 0) head_scale_word_q <= parameter_word_q;
                    coefficient_q <= vocabulary_row_q[2:0] == 0 ? parameter_word_q[23:0] :
                        head_scale_word_q[(int'(vocabulary_row_q[2:0]) << 5) +: 24];
                    op <= H_STREAM_WAIT;
                end
                op[H_STREAM_WAIT_IDX] : if (head_dot_done) begin linear_acc_q <= head_dot_acc; op <= H_COEFF; end
                op[H_COEFF_IDX] : begin
                    scalar_a_q <= linear_acc_q; scalar_b_q <= $signed({1'b0, coefficient_q});
                    op <= SC_MULTIPLY;
                end
                op[H_ROUND_IDX] : begin scalar_round_q <= rne_shift64(scalar_product_q, 6'd24); op <= H_NOISE; end
                op[H_NOISE_IDX] : begin
                    // Gumbel-max selection is entirely on RTL. Temperature=0
                    // selects the largest logit, preserving stable lowest-ID ties.
                    noise_product_q <= noise_product_comb;
                    random_q <= llm_random_next(random_q); op <= H_SAMPLE;
                end
                op[H_SAMPLE_IDX] : begin
                    sampled_score_q <= scalar_round_q + rne_shift64(64'(noise_product_q), 6'd8); op <= H_SELECT;
                end
                op[H_SELECT_IDX] : begin
                    if (vocabulary_row_q != 0 && vocabulary_row_q != 2 &&
                        (vocabulary_row_q != 1 || generated_q >= min_new_q) &&
                        sat_s32(sampled_score_q) > best_score_q) begin
                        best_score_q <= sat_s32(sampled_score_q); best_token_q <= vocabulary_row_q;
                    end
                    if (vocabulary_row_q == 4095) op <= O_FINISH;
                    else begin
                        vocabulary_row_q <= vocabulary_row_q + 1'b1; chunk_q <= 0; linear_acc_q <= 0;
                        if (vocabulary_row_q[2:0] == 7) begin
                            p_address_q <= 15'(EMB_SCALE_BASE + ((vocabulary_row_q + 1) >> 3)); return_p <= RET_P_H_SCALE; op <= O_P_REQ;
                        end else op <= H_SCALE;
                    end
                end
                default : ;
            endcase
        end else begin op <= O_IDLE; op_done <= 0; overflow_out <= 0; random_q <= 1; op_fault_q <= 0; end
    end
endmodule
