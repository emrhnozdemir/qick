`timescale 1ns / 1ps

module probe_diff (
  input wire [63:0] p_a_i,
  input wire [63:0] p_b_i,
  input wire dip_i,

  output wire signed [64:0] dp_o,
  output wire [64:0] dp_abs_o,
  output wire pos_o,
  output wire neg_o
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
