`timescale 1ns / 1ps

module early_stop_checker(
  input clk,
  input rst_n,

  input arm_i,
  input flush_i,
  input shot_i,
  input enable_i,
  input [4:0] avg_shift_i,
  input [31:0] warmup_shots_i,
  input [31:0] n_min_i,
  input [15:0] threshold_i,
  input block_en_i,
  input short_confirm_i,
  input [31:0] block_tol_i,
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

  output [9:0] log_entry_o,
  output reg signed [31:0] point_i_o,
  output reg signed [31:0] point_q_o,
  output [31:0] debug_o
);

  wire check;
  wire [4:0] check_exponent;
  wire short_check;
  wire retire;
  wire stopping;
  wire [4:0] retire_shift;
  wire [31:0] counter_debug;

  wire stop;
  wire [4:0] stop_exponent;
  wire saturated;
  wire legacy_stop;
  wire [4:0] legacy_exponent;
  wire short_stop;
  wire [4:0] short_exponent;
  wire signed [57:0] short_snapshot_i;
  wire signed [57:0] short_snapshot_q;
  wire restart = arm_i | flush_i;
  wire sample;

  reg short_mode;
  reg short_enabled;
  reg [15:0] threshold;
  reg [31:0] n_min;
  reg [2:0] confirm;
  reg block_en;
  reg [31:0] block_tol;

  always @(posedge clk) begin
    if (!rst_n) begin
      short_mode <= 0;
      short_enabled <= 0;
      threshold <= 0;
      n_min <= 0;
      confirm <= 0;
      block_en <= 0;
      block_tol <= 0;
    end else if (restart) begin
      short_mode <= short_confirm_i;
      short_enabled <= enable_i & short_confirm_i & ~block_en_i;
      threshold <= threshold_i;
      n_min <= n_min_i;
      confirm <= confirm_i;
      block_en <= block_en_i;
      block_tol <= block_tol_i;
    end
  end

  assign sample = check | (short_enabled & short_check);
  assign stop = ~restart & (short_mode ? short_stop : legacy_stop);
  assign stop_exponent = short_mode ? short_exponent : legacy_exponent;

  wire magnitude_valid;
  wire [58:0] signal_magnitude;
  wire [58:0] noise_magnitude;
  wire [59:0] block_magnitude;
  wire block_valid;
  wire [4:0] magnitude_exponent;
  wire magnitude_power;
  wire verdict_valid;
  wire verdict_passed;
  wire verdict_power;
  wire [4:0] verdict_exponent;
  wire signed [57:0] snapshot_i;
  wire signed [57:0] snapshot_q;
  wire signed [57:0] bank_i;
  wire signed [57:0] bank_q;
  wire bank_select;

  shot_counter counter(
    .clk(clk),
    .rst_n(rst_n),
    .arm_i(arm_i),
    .flush_i(flush_i),
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
    .short_check_o(short_check),
    .retire_o(retire),
    .stopping_o(stopping),
    .emit_o(emit_o),
    .stop_pulse_o(stop_pulse_o),
    .warmup_done_o(warmup_done_o),
    .retire_shift_o(retire_shift),
    .stopped_early_o(stopped_early_o),
    .shots_used_o(shots_used_o),
    .debug_o(counter_debug)
  );

  magnitude_calculator magnitude(
    .clk(clk),
    .rst_n(rst_n),
    .arm_i(restart),
    .sample_i(sample),
    .check_i(check),
    .check_exponent_i(check_exponent),
    .snapshot_select_i(stop_exponent[0]),
    .bank_select_i(bank_select),
    .sum_i_i(sum_i_i),
    .sum_q_i(sum_q_i),
    .diff_i_i(diff_i_i),
    .diff_q_i(diff_q_i),
    .snapshot_i_o(snapshot_i),
    .snapshot_q_o(snapshot_q),
    .bank_i_o(bank_i),
    .bank_q_o(bank_q),
    .valid_o(magnitude_valid),
    .signal_magnitude_o(signal_magnitude),
    .noise_magnitude_o(noise_magnitude),
    .block_magnitude_o(block_magnitude),
    .block_valid_o(block_valid),
    .exponent_o(magnitude_exponent),
    .power_o(magnitude_power)
  );

  threshold_compare compare(
    .clk(clk),
    .rst_n(rst_n),
    .arm_i(restart),
    .enable_i(enable_i),
    .threshold_i(threshold),
    .block_en_i(block_en),
    .block_tol_i(block_tol),
    .n_min_i(n_min),
    .confirm_i(confirm),
    .valid_i(magnitude_valid),
    .signal_magnitude_i(signal_magnitude),
    .noise_magnitude_i(noise_magnitude),
    .block_magnitude_i(block_magnitude),
    .block_valid_i(block_valid),
    .exponent_i(magnitude_exponent),
    .power_i(magnitude_power),
    .stop_o(legacy_stop),
    .stop_exponent_o(legacy_exponent),
    .saturated_o(saturated),
    .verdict_valid_o(verdict_valid),
    .verdict_passed_o(verdict_passed),
    .verdict_power_o(verdict_power),
    .verdict_exponent_o(verdict_exponent)
  );

  short_confirmation short_confirm(
    .clk(clk),
    .rst_n(rst_n),
    .arm_i(restart),
    .enable_i(short_enabled),
    .n_min_i(n_min),
    .confirm_i(confirm),
    .verdict_valid_i(verdict_valid),
    .verdict_passed_i(verdict_passed),
    .verdict_power_i(verdict_power),
    .verdict_exponent_i(verdict_exponent),
    .bank_i_i(bank_i),
    .bank_q_i(bank_q),
    .bank_select_o(bank_select),
    .stop_o(short_stop),
    .stop_exponent_o(short_exponent),
    .snapshot_i_o(short_snapshot_i),
    .snapshot_q_o(short_snapshot_q)
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
        retire_num_i <= stopping ? (short_mode ? short_snapshot_i : snapshot_i) : sum_i_i;
        retire_num_q <= stopping ? (short_mode ? short_snapshot_q : snapshot_q) : sum_q_i;
        retire_window <= retire_shift;
      end
    end
  end

  always @(posedge clk) begin
    if (!rst_n) begin
      point_i_o <= 0;
      point_q_o <= 0;
    end else begin
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

  assign log_entry_o = {saturated_latched, converged, retire_exponent, converged ? 3'd0 : 3'd4};
  assign debug_o = {counter_debug[31:2], short_mode, counter_debug[0]};

endmodule
