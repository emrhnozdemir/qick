`timescale 1ns / 1ps

module signed_step #(
  parameter W = 33
) (
  input pos_i,
  input neg_i,
  input [W-1:0] step_i,

  output signed [W-1:0] delta_o
);

  assign delta_o = pos_i ? $signed(step_i) :
                   neg_i ? -$signed(step_i) : {W{1'b0}};

endmodule
