`timescale 1ns / 1ps

module sign_step #(
  parameter W = 33
) (
  input wire pos_i,
  input wire neg_i,
  input wire [W-1:0] step_i,

  output wire signed [W-1:0] delta_o
);

  assign delta_o = pos_i ? $signed(step_i) :
                   neg_i ? -$signed(step_i) : {W{1'b0}};

endmodule
