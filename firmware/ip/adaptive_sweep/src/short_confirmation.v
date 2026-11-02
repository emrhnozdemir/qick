`timescale 1ns / 1ps

module short_confirmation(
  input clk,
  input rst_n,
  input arm_i,
  input enable_i,
  input [31:0] n_min_i,
  input [2:0] confirm_i,
  input verdict_valid_i,
  input verdict_passed_i,
  input verdict_power_i,
  input [4:0] verdict_exponent_i,
  input signed [57:0] bank_i_i,
  input signed [57:0] bank_q_i,
  output bank_select_o,
  output reg stop_o,
  output reg [4:0] stop_exponent_o,
  output reg signed [57:0] snapshot_i_o,
  output reg signed [57:0] snapshot_q_o
);

  reg pending;
  reg done;
  reg [2:0] passes;

  wire [2:0] required_passes = (confirm_i == 3'd0) ? 3'd1 : confirm_i;
  wire verdict = enable_i & ~done & verdict_valid_i;

  assign bank_select_o = verdict_exponent_i[0];

  always @(posedge clk) begin
    if (!rst_n || arm_i) begin
      pending <= 0;
      done <= 0;
      passes <= 0;
      stop_o <= 0;
      stop_exponent_o <= 0;
      snapshot_i_o <= 0;
      snapshot_q_o <= 0;
    end else begin
      stop_o <= 0;
      if (verdict) begin
        if (pending) begin
          if (!verdict_passed_i) begin
            pending <= 0;
            passes <= 0;
          end else if (passes >= required_passes - 3'd1) begin
            stop_o <= 1;
            pending <= 0;
            done <= 1;
          end else begin
            passes <= passes + 3'd1;
          end
        end else if (verdict_power_i && ((32'd1 << verdict_exponent_i) >= n_min_i) && verdict_passed_i) begin
          snapshot_i_o <= bank_i_i;
          snapshot_q_o <= bank_q_i;
          stop_exponent_o <= verdict_exponent_i;
          passes <= 1;
          if (required_passes == 3'd1) begin
            stop_o <= 1;
            done <= 1;
          end else begin
            pending <= 1;
          end
        end
      end
    end
  end

endmodule
