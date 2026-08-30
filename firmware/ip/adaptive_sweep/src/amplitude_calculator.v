`timescale 1ns / 1ps

module amplitude_calculator(
  input clk,
  input rst_n,

  input s_axis_tvalid,
  input s_axis_tready,
  input [63:0] s_axis_tdata,

  input arm_i,
  input [4:0] avg_shift_i,
  input [31:0] warmup_shots_i,
  input [31:0] n_min_i,

  input estop_en_i,
  input estop_hold_i,
  input [15:0] threshold_i,
  input [2:0] confirm_i,

  output warmup_done_o,
  output early_stop_o,
  output early_pulse_o,
  output [31:0] n_used_o,

  output [31:0] mean_i_o,
  output [31:0] mean_q_o,
  output log_wr_o,
  output [15:0] log_entry_o,

  output [63:0] power_o,
  output power_valid_o
);

  (* MARK_DEBUG = "TRUE" *) reg signed [31:0] input_i;
  (* MARK_DEBUG = "TRUE" *) reg signed [31:0] input_q;
  (* MARK_DEBUG = "TRUE" *) reg input_valid;
  (* MARK_DEBUG = "TRUE" *) reg input_ready;

  always @(posedge clk) begin
    if (!rst_n) begin
      input_i <= 0;
      input_q <= 0;
      input_valid <= 0;
      input_ready <= 0;
    end else begin
      input_i <= s_axis_tdata[31:0];
      input_q <= s_axis_tdata[63:32];
      input_valid <= s_axis_tvalid;
      input_ready <= s_axis_tready;
    end
  end

  wire shot_accepted = input_valid & input_ready;

  (* MARK_DEBUG = "TRUE" *) reg signed [31:0] shot_data_i;
  (* MARK_DEBUG = "TRUE" *) reg signed [31:0] shot_data_q;
  (* MARK_DEBUG = "TRUE" *) reg shot_valid;

  always @(posedge clk) begin
    if (!rst_n) begin
      shot_data_i <= 0;
      shot_data_q <= 0;
      shot_valid <= 0;
    end else begin
      shot_data_i <= input_i;
      shot_data_q <= input_q;
      shot_valid <= shot_accepted;
    end
  end

  (* max_fanout = 64 *) wire acc_first;
  (* max_fanout = 64 *) wire acc_enable;
  wire acc_subtract;
  (* MARK_DEBUG = "TRUE" *) wire emit;

  (* MARK_DEBUG = "TRUE" *) wire signed [57:0] sum_i;
  (* MARK_DEBUG = "TRUE" *) wire signed [57:0] sum_q;
  (* MARK_DEBUG = "TRUE" *) wire signed [57:0] diff_i;
  (* MARK_DEBUG = "TRUE" *) wire signed [57:0] diff_q;

  (* MARK_DEBUG = "TRUE" *) wire signed [31:0] point_i;
  (* MARK_DEBUG = "TRUE" *) wire signed [31:0] point_q;

  accumulator acc(
    .clk(clk),
    .rst_n(rst_n),
    .first_i(acc_first),
    .en_i(acc_enable),
    .i_i(shot_data_i),
    .q_i(shot_data_q),
    .sum_i_o(sum_i),
    .sum_q_o(sum_q)
  );

  diff_accumulator dacc(
    .clk(clk),
    .rst_n(rst_n),
    .first_i(acc_first),
    .en_i(acc_enable),
    .subtract_i(acc_subtract),
    .i_i(shot_data_i),
    .q_i(shot_data_q),
    .diff_i_o(diff_i),
    .diff_q_o(diff_q)
  );

  early_stop_checker stop_check(
    .clk(clk),
    .rst_n(rst_n),
    .arm_i(arm_i),
    .shot_i(shot_valid),
    .enable_i(estop_en_i),
    .avg_shift_i(avg_shift_i),
    .warmup_shots_i(warmup_shots_i),
    .n_min_i(n_min_i),
    .threshold_i(threshold_i),
    .confirm_i(confirm_i),
    .hold_i(estop_hold_i),
    .sum_i_i(sum_i),
    .sum_q_i(sum_q),
    .diff_i_i(diff_i),
    .diff_q_i(diff_q),
    .acc_first_o(acc_first),
    .acc_enable_o(acc_enable),
    .acc_subtract_o(acc_subtract),
    .warmup_done_o(warmup_done_o),
    .stop_pulse_o(early_pulse_o),
    .emit_o(emit),
    .stopped_early_o(early_stop_o),
    .shots_used_o(n_used_o),
    .log_entry_o(log_entry_o),
    .point_i_o(point_i),
    .point_q_o(point_q)
  );

  assign mean_i_o = point_i;
  assign mean_q_o = point_q;

  reg [1:0] emit_pipe;

  always @(posedge clk) begin
    if (!rst_n)
      emit_pipe <= 0;
    else
      emit_pipe <= {emit_pipe[0], emit};
  end

  (* MARK_DEBUG = "TRUE" *) wire emit_ready = emit_pipe[1];

  assign log_wr_o = emit_ready;

  square_summer summer(
    .clk(clk),
    .rst_n(rst_n),
    .start_i(emit_ready),
    .i_i(point_i),
    .q_i(point_q),
    .power_o(power_o),
    .valid_o(power_valid_o)
  );

endmodule
