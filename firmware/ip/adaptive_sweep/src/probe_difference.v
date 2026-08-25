`timescale 1ns / 1ps

module probe_difference (
  input [63:0] p_a_i,
  input [63:0] p_b_i,
  input dip_i,

  output signed [64:0] dp_o,
  output [64:0] dp_abs_o,
  output pos_o,
  output neg_o
);

  wire signed [64:0] raw = $signed({1'b0, p_b_i}) - $signed({1'b0, p_a_i});

  assign dp_o = dip_i ? -raw : raw;

  abs_value #(.W(65)) u_abs (
    .a_i (dp_o),
    .y_o (dp_abs_o)
  );

  assign pos_o = ~dp_o[64] & (dp_o != {65{1'b0}});
  assign neg_o = dp_o[64];

endmodule
