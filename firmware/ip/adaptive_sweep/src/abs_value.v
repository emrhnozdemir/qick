`timescale 1ns / 1ps

module abs_value #(
  parameter W = 32
) (
  input wire signed [W-1:0] a_i,

  output wire [W-1:0] y_o
);

  assign y_o = a_i[W-1] ? (~a_i + {{(W-1){1'b0}}, 1'b1}) : a_i;

endmodule
