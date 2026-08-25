`timescale 1ns / 1ps

module magnitude_calculator(
  input clk,
  input rst_n,

  input check_i,
  input [4:0] check_exponent_i,

  input signed [57:0] sum_i_i,
  input signed [57:0] sum_q_i,
  input signed [57:0] diff_i_i,
  input signed [57:0] diff_q_i,

  output reg signed [57:0] snapshot_i_o,
  output reg signed [57:0] snapshot_q_o,

  output reg valid_o,
  (* MARK_DEBUG = "TRUE" *) output reg [58:0] signal_magnitude_o,
  (* MARK_DEBUG = "TRUE" *) output reg [58:0] noise_magnitude_o,
  output reg [4:0] exponent_o
);

  reg captured;
  reg signed [57:0] capture_diff_i;
  reg signed [57:0] capture_diff_q;
  reg [4:0] capture_exponent;

  always @(posedge clk) begin
    if (!rst_n) begin
      captured <= 0;
      snapshot_i_o <= 0;
      snapshot_q_o <= 0;
      capture_diff_i <= 0;
      capture_diff_q <= 0;
      capture_exponent <= 0;
    end else if (check_i) begin
      captured <= 1;
      snapshot_i_o <= sum_i_i;
      snapshot_q_o <= sum_q_i;
      capture_diff_i <= diff_i_i;
      capture_diff_q <= diff_q_i;
      capture_exponent <= check_exponent_i;
    end else begin
      captured <= 0;
    end
  end

  wire [57:0] folded_sum_i = snapshot_i_o ^ {58{snapshot_i_o[57]}};
  wire [57:0] folded_sum_q = snapshot_q_o ^ {58{snapshot_q_o[57]}};
  wire [57:0] folded_diff_i = capture_diff_i ^ {58{capture_diff_i[57]}};
  wire [57:0] folded_diff_q = capture_diff_q ^ {58{capture_diff_q[57]}};

  wire [58:0] signal_sum = folded_sum_i + folded_sum_q
                         + {57'd0, snapshot_i_o[57]} + {57'd0, snapshot_q_o[57]};
  wire [58:0] noise_sum = folded_diff_i + folded_diff_q
                        + {57'd0, capture_diff_i[57]} + {57'd0, capture_diff_q[57]};

  always @(posedge clk) begin
    if (!rst_n) begin
      valid_o <= 0;
      signal_magnitude_o <= 0;
      noise_magnitude_o <= 0;
      exponent_o <= 0;
    end else if (captured) begin
      valid_o <= 1;
      signal_magnitude_o <= signal_sum;
      noise_magnitude_o <= noise_sum;
      exponent_o <= capture_exponent;
    end else begin
      valid_o <= 0;
    end
  end

endmodule
