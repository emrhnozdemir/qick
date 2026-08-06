`timescale 1ns / 1ps

module signed_diff_accumulator #(
  parameter W = 64
) (
  input wire clk,
  input wire rst_n,
  input wire clr,
  input wire en,
  input wire sub_i,
  input wire signed [W-1:0] d_i,

  output reg signed [W-1:0] q_o,
  output wire signed [W-1:0] q_nxt_o
);

  wire signed [W-1:0] q_sum = sub_i ? (q_o - d_i) : (q_o + d_i);

  assign q_nxt_o = clr ? {W{1'b0}} : (en ? q_sum : q_o);

  always @(posedge clk) begin
    if (!rst_n)
      q_o <= {W{1'b0}};
    else if (clr)
      q_o <= {W{1'b0}};
    else if (en)
      q_o <= q_sum;
    else
      q_o <= q_o;
  end

endmodule
