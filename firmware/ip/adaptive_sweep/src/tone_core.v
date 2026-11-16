`timescale 1ns / 1ps

module tone_core(
  input clk,
  input rst_n,

  input enable_i,
  input select_i,
  input cfg_sweep_i,
  input cfg_search_i,
  input cfg_ratio_i,
  input [31:0] dt1_i,
  input [31:0] dt2_i,
  input [31:0] dt3_i,
  input [31:0] dt4_i,

  input start_i,
  input run_kw_i,
  input arm_i,
  input freq_ack_i,
  input dest_i,
  input finish_seen_i,

  input s_axis_tvalid,
  input [63:0] s_axis_tdata,

  input [31:0] step_i,
  input [15:0] n_points_i,
  input [4:0] avg_shift_i,
  input [31:0] warmup_shots_i,
  input [31:0] n_min_i,
  input search_mode_i,
  input estop_en_i,
  input estop_hold_i,
  input [15:0] threshold_i,
  input block_en_i,
  input short_confirm_i,
  input [31:0] block_tol_i,
  input [2:0] confirm_i,
  input [31:0] min_step_i,
  input [15:0] max_iteration_i,

  output pf_freq_valid_o,
  output pf_finish_o,
  output eng_freq_valid_o,
  output eng_probe_arm_o,
  output eng_done_o,
  output early_pulse_o,
  output power_valid_o,

  output [31:0] status_o,
  output [31:0] best_freq_o,
  output [31:0] n_used_o,
  output [31:0] diag_o,
  output [31:0] freq_word_o,
  output [31:0] mean_i_o,
  output [31:0] mean_q_o,
  output [31:0] result_o,
  output [31:0] result_flags_o,
  output [31:0] next_freq_o,
  output [31:0] gen_base_o,
  output [36:0] ro_base_o,
  output [34:0] ratio_o
);

  wire [31:0] cfg_start;
  wire [31:0] cfg_flo;
  wire [31:0] cfg_fhi;
  wire [31:0] cfg_x0;

  tone_registers registers(
    .clk(clk),
    .rst_n(rst_n),
    .select_i(select_i),
    .cfg_sweep_i(cfg_sweep_i),
    .cfg_search_i(cfg_search_i),
    .cfg_ratio_i(cfg_ratio_i),
    .dt1_i(dt1_i),
    .dt2_i(dt2_i),
    .dt3_i(dt3_i),
    .dt4_i(dt4_i),
    .start_freq_o(cfg_start),
    .f_lo_o(cfg_flo),
    .f_hi_o(cfg_fhi),
    .x0_o(cfg_x0),
    .gen_base_o(gen_base_o),
    .ro_base_o(ro_base_o),
    .ratio_o(ratio_o)
  );

  wire start_now = start_i & enable_i;
  wire run_kw = run_kw_i & enable_i;

  wire pf_waiting;
  wire [31:0] best_freq;
  wire [31:0] pf_best_mean_i;
  wire [31:0] pf_best_mean_q;
  wire [15:0] pf_point_idx;
  wire [31:0] pf_frequency;

  wire ac_warmup_done;
  wire ac_early_stop;
  wire [31:0] ac_n_used;
  wire [31:0] ac_mean_i;
  wire [31:0] ac_mean_q;
  wire ac_log_wr;
  wire [9:0] ac_log_entry;
  wire [63:0] ac_power;
  wire ac_power_valid;
  reg [15:0] nconv_cnt;

  wire [31:0] eng_freq_word;
  wire eng_busy;
  wire eng_converged;
  wire eng_capped;
  wire eng_nothing;
  wire eng_window;
  wire [31:0] eng_x;
  wire [15:0] eng_iter;

  amplitude_calculator u_amplitude_calculator (
    .clk               (clk),
    .rst_n             (rst_n),
    .s_axis_tvalid     (s_axis_tvalid & enable_i),
    .s_axis_tdata      (s_axis_tdata),
    .arm_i             (arm_i),
    .flush_i           (start_i | run_kw_i),
    .avg_shift_i       (avg_shift_i),
    .warmup_shots_i    (warmup_shots_i),
    .n_min_i           (n_min_i),
    .estop_en_i        (estop_en_i),
    .estop_hold_i      (estop_hold_i),
    .threshold_i       (threshold_i),
    .block_en_i        (block_en_i),
    .short_confirm_i   (short_confirm_i),
    .block_tol_i       (block_tol_i),
    .confirm_i         (confirm_i),
    .warmup_done_o     (ac_warmup_done),
    .early_stop_o      (ac_early_stop),
    .early_pulse_o     (early_pulse_o),
    .n_used_o          (ac_n_used),
    .mean_i_o          (ac_mean_i),
    .mean_q_o          (ac_mean_q),
    .log_wr_o          (ac_log_wr),
    .log_entry_o       (ac_log_entry),
    .power_o           (ac_power),
    .power_valid_o     (ac_power_valid),
    .debug_o           ()
  );

  always @(posedge clk) begin
    if (!rst_n)
      nconv_cnt <= 16'd0;
    else if (start_i | run_kw_i)
      nconv_cnt <= 16'd0;
    else if (ac_log_wr & ~ac_log_entry[8])
      nconv_cnt <= nconv_cnt + 16'd1;
  end

  wire grid_valid = ac_power_valid & ~dest_i;
  wire search_valid = ac_power_valid & dest_i;

  gradient_engine u_gradient_engine (
    .clk               (clk),
    .rst_n             (rst_n),
    .start_i           (run_kw),
    .abort_i           (start_i),
    .dip_i             (search_mode_i),
    .start_freq_i      (cfg_start),
    .step_i            (step_i),
    .n_points_i        (n_points_i),
    .x0_i              (cfg_x0),
    .f_lo_i            (cfg_flo),
    .f_hi_i            (cfg_fhi),
    .min_step_i        (min_step_i),
    .max_iteration_i   (max_iteration_i),
    .threshold_i       (threshold_i),
    .freq_word_o       (eng_freq_word),
    .freq_valid_o      (eng_freq_valid_o),
    .freq_ack_i        (freq_ack_i),
    .probe_arm_o       (eng_probe_arm_o),
    .amp_valid_i       (search_valid),
    .amp_data_i        (ac_power),
    .busy_o            (eng_busy),
    .done_o            (eng_done_o),
    .converged_o       (eng_converged),
    .capped_o          (eng_capped),
    .nothing_o         (eng_nothing),
    .window_o          (eng_window),
    .x_o               (eng_x),
    .iteration_o       (eng_iter),
    .points_o          (),
    .spacing_o         (),
    .jump_o            (),
    .debug_o           ()
  );

  peak_finder u_peak_finder (
    .clk            (clk),
    .rst_n          (rst_n),
    .start_i        (start_now),
    .abort_i        (run_kw_i),
    .start_freq_i   (cfg_start),
    .step_i         (step_i),
    .n_points_i     (n_points_i),
    .dip_i          (search_mode_i),
    .amp_valid_i    (grid_valid),
    .amp_data_i     (ac_power),
    .mean_i_i       (ac_mean_i),
    .mean_q_i       (ac_mean_q),
    .freq_valid_o   (pf_freq_valid_o),
    .finish_o       (pf_finish_o),
    .best_freq_o    (best_freq),
    .best_mean_i_o  (pf_best_mean_i),
    .best_mean_q_o  (pf_best_mean_q),
    .point_idx_o    (pf_point_idx),
    .frequency_o    (pf_frequency),
    .waiting_o      (pf_waiting)
  );

  assign power_valid_o = ac_power_valid;

  assign status_o = {pf_point_idx,
                     eng_freq_valid_o,
                     eng_busy,
                     eng_converged,
                     eng_capped,
                     dest_i,
                     estop_en_i,
                     eng_window,
                     ac_early_stop,
                     ac_warmup_done,
                     3'd0,
                     search_mode_i,
                     pf_waiting,
                     finish_seen_i,
                     (dest_i & eng_nothing)};
  assign best_freq_o = best_freq;
  assign n_used_o = ac_n_used;
  assign diag_o = {nconv_cnt, 6'd0, ac_log_entry};
  assign freq_word_o = eng_freq_word;
  assign mean_i_o = dest_i ? ac_mean_i : pf_best_mean_i;
  assign mean_q_o = dest_i ? ac_mean_q : pf_best_mean_q;
  assign result_o = dest_i ? eng_x : best_freq;
  assign result_flags_o = dest_i ? {eng_iter, 12'd0, eng_window, eng_nothing, eng_capped, eng_converged} : 32'd0;
  assign next_freq_o = dest_i ? eng_freq_word : pf_frequency;

endmodule
