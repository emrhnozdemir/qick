`timescale 1ns / 1ps

module early_stop_checker(
  input clk,
  input rst_n,

  input arm_i,
  input shot_i,
  input enable_i,
  input [4:0] avg_shift_i,
  input [31:0] warmup_shots_i,
  input [31:0] n_min_i,
  input [15:0] threshold_i,
  input [2:0] confirm_i,
  input hold_i,

  input signed [57:0] sum_i_i,
  input signed [57:0] sum_q_i,
  input signed [57:0] diff_i_i,
  input signed [57:0] diff_q_i,

  output acc_first_o,
  output acc_enable_o,
  output acc_subtract_o,

  output warmup_done_o,
  output stop_pulse_o,
  output emit_o,
  output stopped_early_o,
  output [31:0] shots_used_o,

  output [15:0] log_entry_o,
  (* MARK_DEBUG = "TRUE" *) output reg signed [31:0] point_i_o,
  (* MARK_DEBUG = "TRUE" *) output reg signed [31:0] point_q_o,
  (* MARK_DEBUG = "TRUE" *) output reg point_valid_o
);

  wire check;
  wire [4:0] check_exponent;
  wire retire;
  wire stopping;
  wire [4:0] retire_shift;

  wire stop;
  wire [4:0] stop_exponent;
  wire saturated;

  wire magnitude_valid;
  wire [58:0] signal_magnitude;
  wire [58:0] noise_magnitude;
  wire [4:0] magnitude_exponent;
  wire signed [57:0] snapshot_i;
  wire signed [57:0] snapshot_q;

  shot_counter counter(
    .clk(clk),
    .rst_n(rst_n),
    .arm_i(arm_i),
    .shot_i(shot_i),
    .avg_shift_i(avg_shift_i),
    .warmup_shots_i(warmup_shots_i),
    .enable_i(enable_i),
    .hold_i(hold_i),
    .stop_i(stop),
    .stop_exponent_i(stop_exponent),
    .acc_first_o(acc_first_o),
    .acc_enable_o(acc_enable_o),
    .acc_subtract_o(acc_subtract_o),
    .check_o(check),
    .check_exponent_o(check_exponent),
    .retire_o(retire),
    .stopping_o(stopping),
    .emit_o(emit_o),
    .stop_pulse_o(stop_pulse_o),
    .warmup_done_o(warmup_done_o),
    .retire_shift_o(retire_shift),
    .stopped_early_o(stopped_early_o),
    .shots_used_o(shots_used_o)
  );

  magnitude_calculator magnitude(
    .clk(clk),
    .rst_n(rst_n),
    .check_i(check),
    .check_exponent_i(check_exponent),
    .sum_i_i(sum_i_i),
    .sum_q_i(sum_q_i),
    .diff_i_i(diff_i_i),
    .diff_q_i(diff_q_i),
    .snapshot_i_o(snapshot_i),
    .snapshot_q_o(snapshot_q),
    .valid_o(magnitude_valid),
    .signal_magnitude_o(signal_magnitude),
    .noise_magnitude_o(noise_magnitude),
    .exponent_o(magnitude_exponent)
  );

  threshold_compare compare(
    .clk(clk),
    .rst_n(rst_n),
    .arm_i(arm_i),
    .enable_i(enable_i),
    .threshold_i(threshold_i),
    .n_min_i(n_min_i),
    .confirm_i(confirm_i),
    .valid_i(magnitude_valid),
    .signal_magnitude_i(signal_magnitude),
    .noise_magnitude_i(noise_magnitude),
    .exponent_i(magnitude_exponent),
    .stop_o(stop),
    .stop_exponent_o(stop_exponent),
    .saturated_o(saturated)
  );

  reg signed [57:0] retire_num_i;
  reg signed [57:0] retire_num_q;
  reg [4:0] retire_window;
  reg retire_valid;

  always @(posedge clk) begin
    if (!rst_n) begin
      retire_num_i <= 0;
      retire_num_q <= 0;
      retire_window <= 0;
      retire_valid <= 0;
    end else begin
      retire_valid <= retire;
      if (retire) begin
        retire_num_i <= stopping ? snapshot_i : sum_i_i;
        retire_num_q <= stopping ? snapshot_q : sum_q_i;
        retire_window <= retire_shift;
      end
    end
  end

  always @(posedge clk) begin
    if (!rst_n) begin
      point_i_o <= 0;
      point_q_o <= 0;
      point_valid_o <= 0;
    end else begin
      point_valid_o <= retire_valid;
      if (retire_valid) begin
        point_i_o <= retire_num_i[retire_window +: 32];
        point_q_o <= retire_num_q[retire_window +: 32];
      end
    end
  end

  reg converged;
  reg saturated_latched;
  reg [4:0] retire_exponent;

  always @(posedge clk) begin
    if (!rst_n) begin
      converged <= 0;
      saturated_latched <= 0;
      retire_exponent <= 0;
    end else if (retire) begin
      converged <= stopping;
      saturated_latched <= saturated;
      retire_exponent <= stopping ? stop_exponent : 5'd0;
    end
  end

  assign log_entry_o = {6'd0, saturated_latched, converged, retire_exponent,
                        converged ? 3'd0 : 3'd4};

endmodule
