`timescale 1ns / 1ps

module probe_diff (
  input wire [35:0] p_a_i,
  input wire [35:0] p_b_i,
  input wire dip_i,

  output wire signed [36:0] dp_o,
  output wire [36:0] dp_abs_o,
  output wire pos_o,
  output wire neg_o
);

  wire signed [36:0] raw = $signed({1'b0, p_b_i}) - $signed({1'b0, p_a_i});

  assign dp_o = dip_i ? -raw : raw;

  abs_value #(.W(37)) u_abs (
    .a_i (dp_o),
    .y_o (dp_abs_o)
  );

  assign pos_o = ~dp_o[36] & (dp_o != {37{1'b0}});
  assign neg_o = dp_o[36];

endmodule
