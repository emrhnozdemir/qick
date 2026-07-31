`timescale 1ns / 1ps

module round_shift #(
  parameter W = 33
) (
  input wire signed [W-1:0] d_i,
  input wire [4:0] sh_i,

  output wire signed [W-1:0] y_o
);

  wire signed [W-1:0] one = {{(W-1){1'b0}}, 1'b1};
  wire signed [W-1:0] rnd = (sh_i == 5'd0) ? {W{1'b0}} : (one <<< (sh_i - 5'd1));

  assign y_o = (d_i + rnd) >>> sh_i;

endmodule
