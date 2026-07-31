`timescale 1ns / 1ps

module ctrl_status_reg (
  input wire clk,
  input wire rst_n,

  input wire cfg_sweep_i,
  input wire cfg_meas_i,
  input wire cfg_search_i,
  input wire [31:0] dt1_i,
  input wire [31:0] dt2_i,
  input wire [31:0] dt3_i,
  input wire [31:0] dt4_i,

  input wire ctrl_wr_i,
  input wire [31:0] ctrl_wr_data_i,

  (* mark_debug = "true" *) output reg [31:0] start_freq_o,
  (* mark_debug = "true" *) output reg [31:0] step_o,
  (* mark_debug = "true" *) output reg [31:0] n_points_o,
  (* mark_debug = "true" *) output reg [31:0] averager_o,
  (* mark_debug = "true" *) output reg [31:0] nsamp_o,
  (* mark_debug = "true" *) output reg [31:0] n0_o,
  (* mark_debug = "true" *) output reg [31:0] n_min_o,
  (* mark_debug = "true" *) output reg [31:0] f_lo_o,
  (* mark_debug = "true" *) output reg [31:0] f_hi_o,
  (* mark_debug = "true" *) output reg [15:0] m_min_o,
  (* mark_debug = "true" *) output reg [15:0] m_max_o,

  output wire [31:0] ctrl_o,
  output wire search_mode_o,
  output wire [2:0] reduce_sel_o,
  output wire estop_hold_o,
  output wire prescale_en_o,
  output wire estop_en_o,

  input wire [15:0] point_idx_i,
  input wire busy_i,
  input wire finish_seen_i,
  input wire warmup_done_i,
  input wire early_stop_i,
  input wire dest_i,
  input wire eng_freq_valid_i,
  input wire eng_busy_i,
  input wire eng_converged_i,
  input wire eng_capped_i,

  output wire [31:0] status_o
);

  (* mark_debug = "true" *) reg [31:0] ctrl_r;

  assign ctrl_o = ctrl_r;
  assign search_mode_o = ctrl_r[0];
  assign reduce_sel_o = ctrl_r[3:1];
  assign estop_hold_o = ctrl_r[4];
  assign prescale_en_o = ctrl_r[5];
  assign estop_en_o = ctrl_r[6];

  assign status_o = {point_idx_i,
                     eng_freq_valid_i,
                     eng_busy_i,
                     eng_converged_i,
                     eng_capped_i,
                     dest_i,
                     estop_en_o,
                     prescale_en_o,
                     early_stop_i,
                     warmup_done_i,
                     reduce_sel_o,
                     search_mode_o,
                     busy_i,
                     finish_seen_i,
                     1'b0};

  always @(posedge clk) begin
    if (!rst_n)
      ctrl_r <= 32'd0;
    else if (cfg_meas_i)
      ctrl_r <= dt2_i;
    else if (ctrl_wr_i)
      ctrl_r <= ctrl_wr_data_i;
    else
      ctrl_r <= ctrl_r;
  end

  always @(posedge clk) begin
    if (!rst_n) begin
      start_freq_o <= 32'd0;
      step_o <= 32'd0;
      n_points_o <= 32'd0;
      averager_o <= 32'd0;
    end else if (cfg_sweep_i) begin
      start_freq_o <= dt1_i;
      step_o <= dt2_i;
      n_points_o <= dt3_i;
      averager_o <= dt4_i;
    end else begin
      start_freq_o <= start_freq_o;
      step_o <= step_o;
      n_points_o <= n_points_o;
      averager_o <= averager_o;
    end
  end

  always @(posedge clk) begin
    if (!rst_n) begin
      nsamp_o <= 32'd0;
      n0_o <= 32'd0;
      n_min_o <= 32'd0;
    end else if (cfg_meas_i) begin
      nsamp_o <= dt1_i;
      n0_o <= dt3_i;
      n_min_o <= dt4_i;
    end else begin
      nsamp_o <= nsamp_o;
      n0_o <= n0_o;
      n_min_o <= n_min_o;
    end
  end

  always @(posedge clk) begin
    if (!rst_n) begin
      f_lo_o <= 32'd0;
      f_hi_o <= 32'hFFFFFFFF;
      m_min_o <= 16'd1;
      m_max_o <= 16'd1;
    end else if (cfg_search_i) begin
      f_lo_o <= dt1_i;
      f_hi_o <= dt2_i;
      m_min_o <= dt3_i[15:0];
      m_max_o <= dt4_i[15:0];
    end else begin
      f_lo_o <= f_lo_o;
      f_hi_o <= f_hi_o;
      m_min_o <= m_min_o;
      m_max_o <= m_max_o;
    end
  end

  (* mark_debug = "true" *) reg cfg_sweep_dbg;
  (* mark_debug = "true" *) reg cfg_meas_dbg;
  (* mark_debug = "true" *) reg cfg_search_dbg;
  (* mark_debug = "true" *) reg ctrl_wr_dbg;
  (* mark_debug = "true" *) reg [31:0] ctrl_wr_data_dbg;
  (* mark_debug = "true" *) reg [31:0] status_dbg;
  always @(posedge clk) begin
    if (!rst_n) begin
      cfg_sweep_dbg <= 1'b0;
      cfg_meas_dbg <= 1'b0;
      cfg_search_dbg <= 1'b0;
      ctrl_wr_dbg <= 1'b0;
      ctrl_wr_data_dbg <= 32'd0;
      status_dbg <= 32'd0;
    end else begin
      cfg_sweep_dbg <= cfg_sweep_i;
      cfg_meas_dbg <= cfg_meas_i;
      cfg_search_dbg <= cfg_search_i;
      ctrl_wr_dbg <= ctrl_wr_i;
      ctrl_wr_data_dbg <= ctrl_wr_data_i;
      status_dbg <= status_o;
    end
  end

endmodule
