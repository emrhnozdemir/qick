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

  (* MARK_DEBUG = "TRUE" *) output reg freq_valid_o,
  (* MARK_DEBUG = "TRUE" *) output reg finish_o,

  (* MARK_DEBUG = "TRUE" *) output reg [31:0] best_freq_o,
  output reg [31:0] best_mean_i_o,
  output reg [31:0] best_mean_q_o,
  (* MARK_DEBUG = "TRUE" *) output reg [15:0] point_idx_o
);

  localparam [1:0] S_IDLE = 2'd0, S_SEND_FREQ = 2'd1, S_WAIT_MEAS = 2'd2;

  (* MARK_DEBUG = "TRUE" *) reg [1:0] state;
  reg [1:0] next_state;

  (* MARK_DEBUG = "TRUE" *) reg [31:0] frequency;
  (* MARK_DEBUG = "TRUE" *) reg [31:0] step;
  (* MARK_DEBUG = "TRUE" *) reg [15:0] last_index;
  (* MARK_DEBUG = "TRUE" *) reg [63:0] best_amplitude;
  (* MARK_DEBUG = "TRUE" *) reg last_point;
  (* MARK_DEBUG = "TRUE" *) reg dip;
  reg best_valid;

  (* MARK_DEBUG = "TRUE" *) wire is_better = dip ? (amp_data_i < best_amplitude) : (amp_data_i > best_amplitude);
  wire take_point = is_better | ~best_valid;
  wire [15:0] next_index = point_idx_o + 16'd1;

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
      best_freq_o <= 0;
      best_mean_i_o <= 0;
      best_mean_q_o <= 0;
      point_idx_o <= 0;
      frequency <= 0;
      step <= 0;
      last_index <= 0;
      best_amplitude <= 0;
      last_point <= 0;
      dip <= 0;
      best_valid <= 0;
    end else begin
      case (state)
      S_IDLE: begin
        freq_valid_o <= 0;
        finish_o <= 0;
        if (start_i) begin
          frequency <= start_freq_i;
          step <= step_i;
          last_index <= (n_points_i == 16'd0) ? 16'd0 : (n_points_i - 16'd1);
          point_idx_o <= 0;
          last_point <= (n_points_i <= 16'd1);
          dip <= dip_i;
          best_amplitude <= dip_i ? {64{1'b1}} : {64{1'b0}};
          best_valid <= 0;
          best_freq_o <= 0;
          best_mean_i_o <= 0;
          best_mean_q_o <= 0;
        end
      end

      S_SEND_FREQ: begin
        freq_valid_o <= 1;
        finish_o <= 0;
      end

      S_WAIT_MEAS: begin
        freq_valid_o <= 0;
        if (amp_valid_i) begin
          if (take_point) begin
            best_amplitude <= amp_data_i;
            best_freq_o <= frequency;
            best_mean_i_o <= mean_i_i;
            best_mean_q_o <= mean_q_i;
            best_valid <= 1;
          end else begin
            best_amplitude <= best_amplitude;
            best_freq_o <= best_freq_o;
            best_mean_i_o <= best_mean_i_o;
            best_mean_q_o <= best_mean_q_o;
            best_valid <= best_valid;
          end

          if (last_point)
            finish_o <= 1;
          else begin
            finish_o <= 0;
            frequency <= frequency + step;
            point_idx_o <= next_index;
            last_point <= (next_index == last_index);
          end
        end else
          finish_o <= 0;
      end

      default: begin
        freq_valid_o <= 0;
        finish_o <= 0;
      end
      endcase
    end
  end

endmodule
