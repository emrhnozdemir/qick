`timescale 1ns / 1ps

module best_tracker(
  input clk,
  input rst_n,

  input [1:0] state_i,
  input start_i,
  input dip_i,
  input amp_valid_i,
  input [63:0] amp_data_i,
  input [31:0] mean_i_i,
  input [31:0] mean_q_i,
  input [31:0] frequency_i,

  output [31:0] best_freq_o,
  output [31:0] best_mean_i_o,
  output [31:0] best_mean_q_o
);

  localparam [1:0] S_IDLE = 2'd0, S_WAIT_MEAS = 2'd2;

  reg [63:0] best_amplitude;
  reg [31:0] best_freq;
  reg [31:0] best_mean_i;
  reg [31:0] best_mean_q;
  reg best_valid;
  reg dip;

  wire is_better = dip ? (amp_data_i < best_amplitude) : (amp_data_i > best_amplitude);
  wire take_point = is_better | ~best_valid;

  always @(posedge clk) begin
    if (!rst_n) begin
      best_amplitude <= 0;
      best_freq <= 0;
      best_mean_i <= 0;
      best_mean_q <= 0;
      best_valid <= 0;
      dip <= 0;
    end else begin
      case (state_i)
        S_IDLE:
          if (start_i) begin
            dip <= dip_i;
            best_amplitude <= dip_i ? {64{1'b1}} : {64{1'b0}};
            best_valid <= 0;
            best_freq <= 0;
            best_mean_i <= 0;
            best_mean_q <= 0;
          end

        S_WAIT_MEAS:
          if (amp_valid_i && take_point) begin
            best_amplitude <= amp_data_i;
            best_freq <= frequency_i;
            best_mean_i <= mean_i_i;
            best_mean_q <= mean_q_i;
            best_valid <= 1;
          end
      endcase
    end
  end

  assign best_freq_o = best_freq;
  assign best_mean_i_o = best_mean_i;
  assign best_mean_q_o = best_mean_q;

endmodule
