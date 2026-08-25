`timescale 1ns / 1ps

module value_comparator #(
  parameter W = 32
) (
  input [W-1:0] a_i,
  input [W-1:0] b_i,
  input is_signed_i,

  output gt_o,
  output ge_o,
  output eq_o
);

  wire sgt = $signed(a_i) > $signed(b_i);
  wire ugt = a_i > b_i;

  assign eq_o = (a_i == b_i);
  assign gt_o = is_signed_i ? sgt : ugt;
  assign ge_o = gt_o | eq_o;

endmodule
