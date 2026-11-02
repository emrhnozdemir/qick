`timescale 1ns / 1ps

module sweep_debug (
  input clk,
  input rst_n,

  input [3:0] read_sel_i,
  input job_start_i,
  input op_strobe_i,
  input [4:0] op_i,
  input op_unknown_i,
  input read_held_i,
  input getfreq_idle_i,

  input rdy_i,
  input vld_i,
  input res_pend_i,
  input dest_i,
  input finish_seen_i,
  input int_en_i,
  input draining_i,
  input arm_pend_i,
  input tvalid_i,
  input [31:0] drain_drop_cnt_i,
  input [15:0] nconv_i,
  input [31:0] best_freq_i,
  input [31:0] resp_dt1_i,
  input [31:0] resp_dt2_i,

  input pf_waiting_i,
  input pf_freq_valid_i,
  input [15:0] pf_point_idx_i,

  input [31:0] eng_flags_i,
  input [31:0] eng_spacing_i,
  input [31:0] eng_freq_word_i,
  input [31:0] eng_x_i,
  input [15:0] eng_iter_i,
  input [15:0] eng_points_i,
  input [31:0] eng_jump_i,

  input [31:0] ac_flags_i,
  input [63:0] ac_power_i,
  input ac_power_valid_i,
  input [31:0] ac_mean_i_i,
  input [31:0] ac_mean_q_i,
  input [31:0] ac_n_used_i,
  input [9:0] ac_log_entry_i,

  input [31:0] cfg_start_i,
  input [31:0] cfg_step_i,
  input [15:0] cfg_npoints_i,
  input [4:0] cfg_avg_shift_i,
  input [31:0] cfg_warmup_i,
  input [31:0] cfg_nmin_i,
  input [31:0] cfg_flo_i,
  input [31:0] cfg_fhi_i,
  input [15:0] threshold_i,
  input [31:0] block_tol_i,
  input [31:0] ctrl_i,
  input axi_commit_i,
  input [4:0] axi_target_i,
  input axi_bad_target_i,

  output reg [31:0] view_dt1_o,
  output reg [31:0] view_dt2_o
);

  reg [3:0] read_sel;
  reg job_start, op_strobe, op_unknown, read_held, getfreq_idle;
  reg [4:0] op;
  reg rdy, vld, res_pend, dest, finish_seen, int_en, draining, arm_pend, tvalid;
  reg [31:0] drain_drop_cnt, best_freq, resp_dt1, resp_dt2;
  reg [15:0] nconv;
  reg pf_waiting, pf_freq_valid;
  reg [15:0] pf_point_idx;
  reg [31:0] eng_flags, eng_spacing, eng_freq_word, eng_x, eng_jump;
  reg [15:0] eng_iter, eng_points;
  reg [31:0] ac_flags, ac_mean_i, ac_mean_q, ac_n_used;
  reg [63:0] ac_power;
  reg ac_power_valid;
  reg [9:0] ac_log_entry;
  wire [31:0] cfg_start = cfg_start_i;
  wire [31:0] cfg_step = cfg_step_i;
  wire [31:0] cfg_warmup = cfg_warmup_i;
  wire [31:0] cfg_nmin = cfg_nmin_i;
  wire [31:0] cfg_flo = cfg_flo_i;
  wire [31:0] cfg_fhi = cfg_fhi_i;
  wire [31:0] block_tol = block_tol_i;
  wire [31:0] ctrl = ctrl_i;
  wire [15:0] cfg_npoints = cfg_npoints_i;
  wire [15:0] threshold = threshold_i;
  wire [4:0] cfg_avg_shift = cfg_avg_shift_i;
  reg axi_commit, axi_bad_target;
  reg [4:0] axi_target;

  always @(posedge clk) begin
    read_sel <= read_sel_i;
    job_start <= job_start_i;
    op_strobe <= op_strobe_i;
    op <= op_i;
    op_unknown <= op_unknown_i;
    read_held <= read_held_i;
    getfreq_idle <= getfreq_idle_i;
    rdy <= rdy_i;
    vld <= vld_i;
    res_pend <= res_pend_i;
    dest <= dest_i;
    finish_seen <= finish_seen_i;
    int_en <= int_en_i;
    draining <= draining_i;
    arm_pend <= arm_pend_i;
    tvalid <= tvalid_i;
    drain_drop_cnt <= drain_drop_cnt_i;
    nconv <= nconv_i;
    best_freq <= best_freq_i;
    resp_dt1 <= resp_dt1_i;
    resp_dt2 <= resp_dt2_i;
    pf_waiting <= pf_waiting_i;
    pf_freq_valid <= pf_freq_valid_i;
    pf_point_idx <= pf_point_idx_i;
    eng_flags <= eng_flags_i;
    eng_spacing <= eng_spacing_i;
    eng_freq_word <= eng_freq_word_i;
    eng_x <= eng_x_i;
    eng_iter <= eng_iter_i;
    eng_points <= eng_points_i;
    eng_jump <= eng_jump_i;
    ac_flags <= ac_flags_i;
    ac_power <= ac_power_i;
    ac_power_valid <= ac_power_valid_i;
    ac_mean_i <= ac_mean_i_i;
    ac_mean_q <= ac_mean_q_i;
    ac_n_used <= ac_n_used_i;
    ac_log_entry <= ac_log_entry_i;
    axi_commit <= axi_commit_i;
    axi_target <= axi_target_i;
    axi_bad_target <= axi_bad_target_i;
  end

  reg [4:0] last_op;
  reg [7:0] op_count;
  reg [15:0] getfreq_idle_cnt;
  reg [4:0] errors;
  reg [15:0] commit_count;
  reg [4:0] last_target;

  wire eng_measuring = eng_flags[9];
  wire power_expected = dest ? eng_measuring : pf_waiting;
  wire start_busy = job_start & ~rdy;
  wire stray_power = ac_power_valid & ~power_expected;

  always @(posedge clk) begin
    if (!rst_n) begin
      last_op <= 5'd0;
      op_count <= 8'd0;
    end else if (op_strobe) begin
      last_op <= op;
      if (job_start)
        op_count <= 8'd1;
      else if (op_count != 8'hFF)
        op_count <= op_count + 8'd1;
    end
  end

  always @(posedge clk) begin
    if (!rst_n) begin
      errors <= 5'd0;
      getfreq_idle_cnt <= 16'd0;
    end else if (job_start) begin
      errors <= {4'd0, start_busy};
      getfreq_idle_cnt <= 16'd0;
    end else begin
      errors <= errors | {stray_power, axi_bad_target, read_held, op_unknown, 1'b0};
      if (getfreq_idle & (getfreq_idle_cnt != 16'hFFFF))
        getfreq_idle_cnt <= getfreq_idle_cnt + 16'd1;
    end
  end

  always @(posedge clk) begin
    if (!rst_n) begin
      commit_count <= 16'd0;
      last_target <= 5'd0;
    end else if (axi_commit) begin
      commit_count <= commit_count + 16'd1;
      last_target <= axi_target;
    end
  end

  wire [31:0] top_word = {op_count, last_op, eng_flags[16:12], 1'b0,
                          rdy, vld, res_pend, dest, pf_waiting, finish_seen,
                          int_en, draining, arm_pend, tvalid,
                          eng_flags[8], pf_freq_valid, ac_flags[5]};
  wire [31:0] errors_word = {getfreq_idle_cnt, 11'd0, errors};

  always @(posedge clk) begin
    if (!rst_n) begin
      view_dt1_o <= 32'd0;
      view_dt2_o <= 32'd0;
    end else begin
      case (read_sel)
        4'd0: begin view_dt1_o <= top_word; view_dt2_o <= errors_word; end
        4'd1: begin view_dt1_o <= eng_flags; view_dt2_o <= {eng_points, eng_iter}; end
        4'd2: begin view_dt1_o <= eng_freq_word; view_dt2_o <= eng_x; end
        4'd3: begin view_dt1_o <= eng_spacing; view_dt2_o <= eng_jump; end
        4'd4: begin view_dt1_o <= ac_power[31:0]; view_dt2_o <= ac_power[63:32]; end
        4'd5: begin view_dt1_o <= ac_mean_i; view_dt2_o <= ac_mean_q; end
        4'd6: begin view_dt1_o <= ac_n_used; view_dt2_o <= {nconv, 6'd0, ac_log_entry}; end
        4'd7: begin view_dt1_o <= ac_flags; view_dt2_o <= best_freq; end
        4'd8: begin view_dt1_o <= cfg_start; view_dt2_o <= cfg_step; end
        4'd9: begin view_dt1_o <= {cfg_npoints, pf_point_idx}; view_dt2_o <= {threshold, ctrl[19:17], 8'd0, cfg_avg_shift}; end
        4'd10: begin view_dt1_o <= cfg_warmup; view_dt2_o <= cfg_nmin; end
        4'd11: begin view_dt1_o <= cfg_flo; view_dt2_o <= cfg_fhi; end
        4'd12: begin view_dt1_o <= 32'd0; view_dt2_o <= ctrl; end
        4'd13: begin view_dt1_o <= block_tol; view_dt2_o <= {commit_count, 11'd0, last_target}; end
        4'd14: begin view_dt1_o <= drain_drop_cnt; view_dt2_o <= 32'd0; end
        4'd15: begin view_dt1_o <= resp_dt1; view_dt2_o <= resp_dt2; end
      endcase
    end
  end

endmodule
