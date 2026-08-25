`timescale 1ns / 1ps

module event_counter #(
  parameter W = 16
) (
  input clk,
  input rst_n,
  input clr,
  input en,

  output reg [W-1:0] q_o
);

  always @(posedge clk) begin
    if (!rst_n)
      q_o <= {W{1'b0}};
    else if (clr)
      q_o <= {W{1'b0}};
    else if (en)
      q_o <= q_o + {{(W-1){1'b0}}, 1'b1};
  end

endmodule
