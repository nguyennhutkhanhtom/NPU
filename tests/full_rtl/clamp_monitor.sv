`timescale 1ns/1ps
// Verification-only saturation census, bound into llm_soc. It observes the
// existing clamp sites on the edge that consumes each clamp and never drives
// DUT state. Group A clamps lose information in stored S24 activations (only
// linear sets overflow_out); group B clamps are part of the numeric design.
module llm_clamp_monitor #(parameter int NORM_LANES = 4) (
    input logic clk, rst_n,
    input logic [4:0] graph,
    input logic linear_stage4,
    input logic signed [63:0] scalar_round,
    input logic e_clamp, nr_clamp, n_clamp, r_clamp, b_add_clamp, s_clamp, b_clamp,
    input logic signed [63:0] lane_round [0:31], lane_raw [0:31],
    input logic norm_clamp,
    input logic signed [63:0] norm_signed [0:NORM_LANES - 1],
    input logic sg_clamp, a_exp_prep, h_select, score_stage1,
    input logic [32:0] exp_difference,
    input logic signed [63:0] sampled_score,
    input logic signed [54:0] scaled_dot
);
    import npu_pkg::*;
    localparam int SITES = 13;
    function automatic string name(input int site);
        case (site)
            0: return "linear"; 1: return "embed"; 2: return "norm_scaled"; 3: return "norm_out";
            4: return "rope"; 5: return "residual"; 6: return "silu"; 7: return "gmul";
            8: return "attention_out"; 9: return "sigmoid_input"; 10: return "exp_underflow";
            11: return "attention_score"; default: return "head_score";
        endcase
    endfunction
    longint samples [0:SITES - 1][0:31];
    longint saturated [0:SITES - 1][0:31];
    function automatic bit out_s24(input logic signed [63:0] x);
        return x > 64'sd8388607 || x < -64'sd8388608;
    endfunction
    function automatic bit out_s16(input logic signed [63:0] x);
        return x > 64'sd32767 || x < -64'sd32768;
    endfunction
    function automatic bit out_s32(input logic signed [63:0] x);
        return x > 64'sd2147483647 || x < -64'sd2147483648;
    endfunction
    task automatic note(input int site, input int count, input int hits);
        samples[site][graph] += count;
        saturated[site][graph] += hits;
    endtask
    initial foreach (samples[s, g]) begin samples[s][g] = 0; saturated[s][g] = 0; end
    always @(posedge clk) if (rst_n) begin
        int hits;
        if (linear_stage4) note(0, 1, out_s24(scalar_round));
        if (e_clamp || nr_clamp || n_clamp || r_clamp || s_clamp || b_clamp) begin
            hits = 0;
            foreach (lane_round[l]) hits += out_s24(lane_round[l]);
            note(e_clamp ? 1 : nr_clamp ? 2 : n_clamp ? 3 : r_clamp ? 4 : s_clamp ? 6 : 7, 32, hits);
        end
        if (b_add_clamp) begin
            hits = 0;
            foreach (lane_raw[l]) hits += out_s24(lane_raw[l]);
            note(5, 32, hits);
        end
        if (norm_clamp) begin
            hits = 0;
            foreach (norm_signed[l]) hits += out_s24(norm_signed[l]);
            note(8, NORM_LANES, hits);
        end
        if (sg_clamp) begin
            hits = 0;
            foreach (lane_round[l]) hits += out_s16(lane_round[l]);
            note(9, 32, hits);
        end
        if (a_exp_prep) note(10, 1, exp_difference >= 33'd1048576);
        if (score_stage1) note(11, 1, out_s32(rne_shift64(64'(scaled_dot), 6'd16)));
        if (h_select) note(12, 1, out_s32(sampled_score));
    end
    final begin
        longint total_samples, total_saturated, group_a, group_b;
        group_a = 0; group_b = 0;
        for (int s = 0; s < SITES; s++) begin
            total_samples = 0; total_saturated = 0;
            for (int g = 0; g < 32; g++) begin
                total_samples += samples[s][g]; total_saturated += saturated[s][g];
                if (saturated[s][g] != 0)
                    $display("CLAMP_PHASE site=%s graph=%0d samples=%0d saturated=%0d",
                        name(s), g, samples[s][g], saturated[s][g]);
            end
            $display("CLAMP_SITE group=%s site=%s samples=%0d saturated=%0d",
                s < 9 ? "A" : "B", name(s), total_samples, total_saturated);
            if (s < 9) group_a += total_saturated; else group_b += total_saturated;
        end
        $display("CLAMP_MONITOR_SUMMARY group_a_saturated=%0d group_b_saturated=%0d", group_a, group_b);
    end
endmodule

// Elaborate this module as an extra top so every llm_soc instance gets a monitor.
module llm_clamp_binder;
bind llm_soc llm_clamp_monitor #(.NORM_LANES(ATTN_DIV_LANES)) u_clamp_monitor (
    .clk(clk), .rst_n(core_rst_n), .graph(graph),
    .linear_stage4(linear_pipe_valid_q[4] && !op_fault_q), .scalar_round(scalar_round_q),
    .e_clamp(op[E_CLAMP_IDX]), .nr_clamp(op[NR_CLAMP_IDX]), .n_clamp(op[N_CLAMP_IDX]),
    .r_clamp(op[R_CLAMP_IDX]), .b_add_clamp(op[B_ADD_CLAMP_IDX]), .s_clamp(op[S_CLAMP_IDX]),
    .b_clamp(op[B_CLAMP_IDX]), .lane_round(lane_round_q), .lane_raw(lane_raw_q),
    .norm_clamp(!op_fault_q && u_attention_normalize.state == u_attention_normalize.CLAMP),
    .norm_signed(u_attention_normalize.signed_q),
    .sg_clamp(op[SG_CLAMP_IDX]), .a_exp_prep(op[A_EXP_PREP_IDX]), .h_select(head_pipe_valid_q[5]),
    .score_stage1(u_attention_engine.active_q && u_attention_engine.score_valid_q[1]),
    .exp_difference(exp_difference_q), .sampled_score(sampled_score_q),
    .scaled_dot(u_attention_engine.scaled_dot_q));
endmodule
