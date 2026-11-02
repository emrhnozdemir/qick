`timescale 1ns / 1ps

module peak_finder(
  input clk,
  input rst_n,

  input start_i,
  input abort_i,
  input [31:0] start_freq_i,
  input [31:0] step_i,
  input [15:0] n_points_i,
  input dip_i,

  input amp_valid_i,
  input [63:0] amp_data_i,
  input [31:0] mean_i_i,
  input [31:0] mean_q_i,

  output reg freq_valid_o,
  output reg finish_o,

  output [31:0] best_freq_o,
  output [31:0] best_mean_i_o,
  output [31:0] best_mean_q_o,
  output [15:0] point_idx_o,
  output waiting_o
);

  reg waiting;

  wire [31:0] frequency;
  wire last_point;
  wire measured = waiting & amp_valid_i;

  point_walker walker(
    .clk(clk),
    .rst_n(rst_n),
    .start_i(start_i),
    .start_freq_i(start_freq_i),
    .step_i(step_i),
    .n_points_i(n_points_i),
    .measured_i(measured),
    .frequency_o(frequency),
    .point_idx_o(point_idx_o),
    .last_point_o(last_point)
  );

  best_tracker tracker(
    .clk(clk),
    .rst_n(rst_n),
    .start_i(start_i),
    .dip_i(dip_i),
    .measured_i(measured),
    .amp_data_i(amp_data_i),
    .mean_i_i(mean_i_i),
    .mean_q_i(mean_q_i),
    .frequency_i(frequency),
    .best_freq_o(best_freq_o),
    .best_mean_i_o(best_mean_i_o),
    .best_mean_q_o(best_mean_q_o)
  );

  always @(posedge clk) begin
    if (!rst_n) begin
      waiting <= 0;
      freq_valid_o <= 0;
      finish_o <= 0;
    end else if (start_i) begin
      waiting <= 1;
      freq_valid_o <= 1;
      finish_o <= 0;
    end else if (abort_i) begin
      waiting <= 0;
      freq_valid_o <= 0;
      finish_o <= 0;
    end else begin
      if (measured & last_point)
        waiting <= 0;
      freq_valid_o <= measured & ~last_point;
      finish_o <= measured & last_point;
    end
  end

  assign waiting_o = waiting;

endmodule
