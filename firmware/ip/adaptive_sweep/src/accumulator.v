`timescale 1ns / 1ps

module accumulator(
  input clk,
  input rst_n,

  input first_i,
  input en_i,
  input signed [31:0] i_i,
  input signed [31:0] q_i,

  output signed [57:0] sum_i_o,
  output signed [57:0] sum_q_o
);

  wire signed [57:0] shot_i_w = {{26{i_i[31]}}, i_i};
  wire signed [57:0] shot_q_w = {{26{q_i[31]}}, q_i};

  (* MARK_DEBUG = "TRUE" *) reg signed [57:0] total_i;
  (* MARK_DEBUG = "TRUE" *) reg signed [57:0] total_q;

  wire signed [57:0] base_i = first_i ? 58'sd0 : total_i;
  wire signed [57:0] base_q = first_i ? 58'sd0 : total_q;

  wire signed [57:0] next_i = base_i + shot_i_w;
  wire signed [57:0] next_q = base_q + shot_q_w;

  assign sum_i_o = en_i ? next_i : total_i;
  assign sum_q_o = en_i ? next_q : total_q;

  always @(posedge clk) begin
    if (!rst_n) begin
      total_i <= 0;
      total_q <= 0;
    end else if (en_i) begin
      total_i <= next_i;
      total_q <= next_q;
    end
  end

endmodule
