`timescale 1ns / 1ps

module match_counter #(
  parameter W = 16
) (
  input wire clk,
  input wire rst_n,
  input wire clr,
  input wire en,
  input wire [W-1:0] match_i,

  output reg [W-1:0] q_o,
  output wire at_match_o
);

  always @(posedge clk) begin
    if (!rst_n)
      q_o <= {W{1'b0}};
    else if (clr)
      q_o <= {W{1'b0}};
    else if (en)
      q_o <= q_o + {{(W-1){1'b0}}, 1'b1};
    else
      q_o <= q_o;
  end

  assign at_match_o = (q_o == match_i);

endmodule
