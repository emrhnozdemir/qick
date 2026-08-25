`timescale 1ns / 1ps

module diff_accumulator(
  input clk,
  input rst_n,

  input first_i,
  input en_i,
  input subtract_i,
  input signed [31:0] i_i,
  input signed [31:0] q_i,

  output signed [57:0] diff_i_o,
  output signed [57:0] diff_q_o
);

  wire signed [57:0] shot_i_w = {{26{i_i[31]}}, i_i};
  wire signed [57:0] shot_q_w = {{26{q_i[31]}}, q_i};

  (* MARK_DEBUG = "TRUE" *) reg signed [57:0] total_i;
  (* MARK_DEBUG = "TRUE" *) reg signed [57:0] total_q;

  wire signed [57:0] base_i = first_i ? 58'sd0 : total_i;
  wire signed [57:0] base_q = first_i ? 58'sd0 : total_q;

  wire signed [57:0] addend_i = subtract_i ? ~shot_i_w : shot_i_w;
  wire signed [57:0] addend_q = subtract_i ? ~shot_q_w : shot_q_w;

  wire signed [57:0] next_i = base_i + addend_i + {57'd0, subtract_i};
  wire signed [57:0] next_q = base_q + addend_q + {57'd0, subtract_i};

  assign diff_i_o = en_i ? next_i : total_i;
  assign diff_q_o = en_i ? next_q : total_q;

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
