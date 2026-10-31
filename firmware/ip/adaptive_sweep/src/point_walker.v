`timescale 1ns / 1ps

module point_walker(
  input clk,
  input rst_n,

  input [1:0] state_i,
  input start_i,
  input [31:0] start_freq_i,
  input [31:0] step_i,
  input [15:0] n_points_i,
  input amp_valid_i,

  output [31:0] frequency_o,
  output [15:0] point_idx_o,
  output last_point_o
);

  localparam [1:0] S_IDLE = 2'd0, S_WAIT_MEAS = 2'd2;

  reg [31:0] frequency;
  reg [31:0] step;
  reg [15:0] last_index;
  reg [15:0] point_idx;
  reg last_point;

  wire [15:0] next_index = point_idx + 16'd1;

  always @(posedge clk) begin
    if (!rst_n) begin
      frequency <= 0;
      step <= 0;
      last_index <= 0;
      point_idx <= 0;
      last_point <= 0;
    end else begin
      case (state_i)
        S_IDLE:
          if (start_i) begin
            frequency <= start_freq_i;
            step <= step_i;
            last_index <= (n_points_i == 16'd0) ? 16'd0 : (n_points_i - 16'd1);
            point_idx <= 0;
            last_point <= (n_points_i <= 16'd1);
          end

        S_WAIT_MEAS:
          if (amp_valid_i && !last_point) begin
            frequency <= frequency + step;
            point_idx <= next_index;
            last_point <= (next_index == last_index);
          end
      endcase
    end
  end

  assign frequency_o = frequency;
  assign point_idx_o = point_idx;
  assign last_point_o = last_point;

endmodule
