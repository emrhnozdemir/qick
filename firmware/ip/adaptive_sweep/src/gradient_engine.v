`timescale 1ns / 1ps

module gradient_engine(
  input clk,
  input rst_n,

  input start_i,
  input dip_i,
  input [31:0] start_freq_i,
  input [31:0] step_i,
  input [15:0] n_points_i,
  input [31:0] x0_i,
  input [31:0] f_lo_i,
  input [31:0] f_hi_i,
  input [31:0] min_step_i,
  input [15:0] max_iteration_i,
  input [15:0] threshold_i,

  output [31:0] freq_word_o,
  output freq_valid_o,
  input freq_ack_i,
  output probe_arm_o,
  input amp_valid_i,
  input [63:0] amp_data_i,

  output busy_o,
  output done_o,
  output converged_o,
  output capped_o,
  output nothing_o,
  output [31:0] x_o,
  output [15:0] iteration_o,
  output [15:0] points_o,
  output [31:0] spacing_o,
  output [31:0] jump_o,
  output [31:0] debug_o
);

  wire [3:0] state;
  wire [3:0] phase;
  wire [3:0] decision;
  wire measuring;

  wire [67:0] pa, pb;
  wire psub;
  wire [33:0] fa, fb;
  wire fsub;

  wire [67:0] palu;
  wire pless;
  wire [31:0] falu;
  wire fless;
  wire [63:0] sh_out;
  wire [6:0] enc_pos;
  wire enc_zero;
  wire [67:0] acc;
  wire [66:0] t;

  wire [63:0] p, g, pmax, worst;
  wire [31:0] lo, b, hi;
  wire [63:0] gl, gb, gh;
  wire [31:0] target;
  wire [15:0] idx;
  wire grid_last;
  wire [3:0] noise_shift;
  wire seen;
  wire dip;

  wire [31:0] step, min_step;
  wire [31:0] sl, sr;
  wire [63:0] dl, dr;
  wire [31:0] short_side, long_side, span, half;
  wire [6:0] lead_s, lead_d;
  wire [3:0] k;
  wire lower, stop, balanced, side, cap, go_up;
  wire [15:0] iteration;
  wire [31:0] width;

  engine_control control(
    .clk(clk),
    .rst_n(rst_n),
    .start_i(start_i),
    .freq_ack_i(freq_ack_i),
    .amp_valid_i(amp_valid_i),
    .seen_i(seen),
    .grid_last_i(grid_last),
    .stop_i(stop),
    .cap_i(cap),
    .pless_i(pless),
    .p_i(p),
    .g_i(g),
    .pmax_i(pmax),
    .worst_i(worst),
    .gl_i(gl),
    .gb_i(gb),
    .gh_i(gh),
    .dl_i(dl),
    .dr_i(dr),
    .acc_i(acc),
    .t_i(t),
    .target_i(target),
    .step_i(step),
    .lo_i(lo),
    .b_i(b),
    .hi_i(hi),
    .sl_i(sl),
    .sr_i(sr),
    .short_side_i(short_side),
    .long_side_i(long_side),
    .span_i(span),
    .min_step_i(min_step),
    .lead_s_i(lead_s),
    .lead_d_i(lead_d),
    .go_up_i(go_up),
    .state_o(state),
    .phase_o(phase),
    .pa_o(pa),
    .pb_o(pb),
    .psub_o(psub),
    .fa_o(fa),
    .fb_o(fb),
    .fsub_o(fsub),
    .freq_valid_o(freq_valid_o),
    .probe_arm_o(probe_arm_o),
    .measuring_o(measuring),
    .busy_o(busy_o),
    .done_o(done_o),
    .converged_o(converged_o),
    .capped_o(capped_o),
    .nothing_o(nothing_o),
    .decision_o(decision)
  );

  arithmetic_unit arith(
    .clk(clk),
    .rst_n(rst_n),
    .state_i(state),
    .phase_i(phase),
    .start_i(start_i),
    .threshold_i(threshold_i),
    .lower_i(lower),
    .pa_i(pa),
    .pb_i(pb),
    .psub_i(psub),
    .fa_i(fa),
    .fb_i(fb),
    .fsub_i(fsub),
    .pmax_i(pmax),
    .noise_shift_i(noise_shift),
    .half_i(half),
    .k_i(k),
    .palu_o(palu),
    .pless_o(pless),
    .falu_o(falu),
    .fless_o(fless),
    .sh_out_o(sh_out),
    .enc_pos_o(enc_pos),
    .enc_zero_o(enc_zero),
    .acc_o(acc),
    .t_o(t)
  );

  search_points points(
    .clk(clk),
    .rst_n(rst_n),
    .state_i(state),
    .start_i(start_i),
    .dip_i(dip_i),
    .start_freq_i(start_freq_i),
    .n_points_i(n_points_i),
    .x0_i(x0_i),
    .f_lo_i(f_lo_i),
    .f_hi_i(f_hi_i),
    .amp_valid_i(amp_valid_i),
    .amp_data_i(amp_data_i),
    .pless_i(pless),
    .falu_i(falu),
    .enc_pos_i(enc_pos),
    .side_i(side),
    .stop_i(stop),
    .p_o(p),
    .g_o(g),
    .pmax_o(pmax),
    .worst_o(worst),
    .lo_o(lo),
    .b_o(b),
    .hi_o(hi),
    .gl_o(gl),
    .gb_o(gb),
    .gh_o(gh),
    .target_o(target),
    .idx_o(idx),
    .grid_last_o(grid_last),
    .noise_shift_o(noise_shift),
    .seen_o(seen),
    .dip_o(dip)
  );

  step_planner planner(
    .clk(clk),
    .rst_n(rst_n),
    .state_i(state),
    .phase_i(phase),
    .start_i(start_i),
    .step_i(step_i),
    .min_step_i(min_step_i),
    .max_iteration_i(max_iteration_i),
    .palu_i(palu),
    .pless_i(pless),
    .falu_i(falu),
    .fless_i(fless),
    .sh_out_i(sh_out[31:0]),
    .enc_pos_i(enc_pos),
    .enc_zero_i(enc_zero),
    .step_o(step),
    .min_step_o(min_step),
    .sl_o(sl),
    .sr_o(sr),
    .dl_o(dl),
    .dr_o(dr),
    .short_side_o(short_side),
    .long_side_o(long_side),
    .span_o(span),
    .half_o(half),
    .lead_s_o(lead_s),
    .lead_d_o(lead_d),
    .k_o(k),
    .lower_o(lower),
    .stop_o(stop),
    .balanced_o(balanced),
    .side_o(side),
    .cap_o(cap),
    .go_up_o(go_up),
    .iteration_o(iteration),
    .width_o(width)
  );

  assign freq_word_o = target;
  assign x_o = b;
  assign iteration_o = iteration;
  assign points_o = idx;
  assign spacing_o = width;
  assign jump_o = step;
  assign debug_o = {4'd0, phase, decision, k, state, seen, dip, measuring,
                    freq_valid_o, probe_arm_o, busy_o, done_o, converged_o, capped_o,
                    nothing_o, side, balanced};

endmodule
