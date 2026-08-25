`timescale 1ns / 1ps

module square_summer(
  input clk,
  input rst_n,

  input start_i,
  input signed [31:0] i_i,
  input signed [31:0] q_i,

  (* MARK_DEBUG = "TRUE" *) output reg [63:0] power_o,
  (* MARK_DEBUG = "TRUE" *) output reg valid_o
);

  (* MARK_DEBUG = "TRUE" *) wire [63:0] i_squared;
  (* MARK_DEBUG = "TRUE" *) wire [63:0] q_squared;

  squarer square_of_i(
    .clk(clk),
    .rst_n(rst_n),
    .value_i(i_i),
    .square_o(i_squared)
  );

  squarer square_of_q(
    .clk(clk),
    .rst_n(rst_n),
    .value_i(q_i),
    .square_o(q_squared)
  );

  reg [3:0] valid_pipe;

  always @(posedge clk) begin
    if (!rst_n)
      valid_pipe <= 0;
    else
      valid_pipe <= {valid_pipe[2:0], start_i};
  end

  always @(posedge clk) begin
    if (!rst_n) begin
      power_o <= 0;
      valid_o <= 0;
    end else begin
      power_o <= i_squared + q_squared;
      valid_o <= valid_pipe[3];
    end
  end

endmodule
