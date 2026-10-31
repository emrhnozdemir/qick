`timescale 1ns / 1ps

module peak_finder(
  input clk,
  input rst_n,

  input start_i,
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
  output [1:0] state_o,
  output waiting_o
);

  localparam [1:0] S_IDLE = 2'd0, S_SEND_FREQ = 2'd1, S_WAIT_MEAS = 2'd2;

  reg [1:0] state;
  reg [1:0] next_state;

  wire [31:0] frequency;
  wire last_point;

  point_walker walker(
    .clk(clk),
    .rst_n(rst_n),
    .state_i(state),
    .start_i(start_i),
    .start_freq_i(start_freq_i),
    .step_i(step_i),
    .n_points_i(n_points_i),
    .amp_valid_i(amp_valid_i),
    .frequency_o(frequency),
    .point_idx_o(point_idx_o),
    .last_point_o(last_point)
  );

  best_tracker tracker(
    .clk(clk),
    .rst_n(rst_n),
    .state_i(state),
    .start_i(start_i),
    .dip_i(dip_i),
    .amp_valid_i(amp_valid_i),
    .amp_data_i(amp_data_i),
    .mean_i_i(mean_i_i),
    .mean_q_i(mean_q_i),
    .frequency_i(frequency),
    .best_freq_o(best_freq_o),
    .best_mean_i_o(best_mean_i_o),
    .best_mean_q_o(best_mean_q_o)
  );

  always @(posedge clk) begin
    if (!rst_n)
      state <= S_IDLE;
    else
      state <= next_state;
  end

  always @(*) begin
    case (state)
      S_IDLE:
        next_state = start_i ? S_SEND_FREQ : S_IDLE;

      S_SEND_FREQ:
        next_state = S_WAIT_MEAS;

      S_WAIT_MEAS: begin
        if (amp_valid_i)
          next_state = last_point ? S_IDLE : S_SEND_FREQ;
        else
          next_state = S_WAIT_MEAS;
      end

      default:
        next_state = S_IDLE;
    endcase
  end

  always @(posedge clk) begin
    if (!rst_n) begin
      freq_valid_o <= 0;
      finish_o <= 0;
    end else begin
      case (state)
        S_IDLE: begin
          freq_valid_o <= 0;
          finish_o <= 0;
        end

        S_SEND_FREQ: begin
          freq_valid_o <= 1;
          finish_o <= 0;
        end

        S_WAIT_MEAS: begin
          freq_valid_o <= 0;
          finish_o <= amp_valid_i & last_point;
        end

        default: begin
          freq_valid_o <= 0;
          finish_o <= 0;
        end
      endcase
    end
  end

  assign state_o = state;
  assign waiting_o = (state == S_WAIT_MEAS);

endmodule
