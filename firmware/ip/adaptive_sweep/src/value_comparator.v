`timescale 1ns / 1ps

module value_comparator #(
  parameter W = 32
) (
  input wire [W-1:0] a_i,
  input wire [W-1:0] b_i,
  input wire is_signed_i,

  output wire gt_o,
  output wire ge_o,
  output wire eq_o
);

  wire sgt = $signed(a_i) > $signed(b_i);
  wire ugt = a_i > b_i;

  assign eq_o = (a_i == b_i);
  assign gt_o = is_signed_i ? sgt : ugt;
  assign ge_o = gt_o | eq_o;

endmodule
