`timescale 1ns / 1ps

module convergence_patience #(
  parameter W = 8
) (
  input clk,
  input rst_n,
  input clr,
  input step_i,
  input hit_i,
  input [W-1:0] patience_i,

  output reg conv_o
);

  reg [W-1:0] streak;

  wire [W-1:0] streak_next = hit_i ? (streak + {{(W-1){1'b0}}, 1'b1}) : {W{1'b0}};

  always @(posedge clk) begin
    if (!rst_n) begin
      streak <= {W{1'b0}};
      conv_o <= 1'b0;
    end else if (clr) begin
      streak <= {W{1'b0}};
      conv_o <= 1'b0;
    end else if (step_i) begin
      streak <= streak_next;
      conv_o <= conv_o | ((patience_i != {W{1'b0}}) & (streak_next >= patience_i));
    end
  end

endmodule
