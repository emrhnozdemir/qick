`timescale 1ns / 1ps

module magnitude_calculator(
  input clk,
  input rst_n,
  input arm_i,

  input check_i,
  input [4:0] check_exponent_i,
  input [4:0] snapshot_exponent_i,

  input signed [57:0] sum_i_i,
  input signed [57:0] sum_q_i,
  input signed [57:0] diff_i_i,
  input signed [57:0] diff_q_i,

  output signed [57:0] snapshot_i_o,
  output signed [57:0] snapshot_q_o,

  output reg valid_o,
  (* MARK_DEBUG = "TRUE" *) output reg [58:0] signal_magnitude_o,
  (* MARK_DEBUG = "TRUE" *) output reg [58:0] noise_magnitude_o,
  (* MARK_DEBUG = "TRUE" *) output reg [59:0] block_magnitude_o,
  output reg block_valid_o,
  output reg [4:0] exponent_o
);

  reg captured;
  reg signed [57:0] capture_diff_i;
  reg signed [57:0] capture_diff_q;
  reg [4:0] capture_exponent;
  reg signed [58:0] capture_block_i;
  reg signed [58:0] capture_block_q;
  reg capture_block_valid;

  reg signed [57:0] snapshot_i [0:1];
  reg signed [57:0] snapshot_q [0:1];
  reg [1:0] snapshot_valid;
  reg [4:0] snapshot_exponent [0:1];
  assign snapshot_i_o = snapshot_i[snapshot_exponent_i[0]];
  assign snapshot_q_o = snapshot_q[snapshot_exponent_i[0]];
  wire signed [57:0] capture_sum_i = snapshot_i[capture_exponent[0]];
  wire signed [57:0] capture_sum_q = snapshot_q[capture_exponent[0]];

  wire previous_bank = ~check_exponent_i[0];
  wire signed [58:0] previous_i = {snapshot_i[previous_bank][57], snapshot_i[previous_bank]};
  wire signed [58:0] previous_q = {snapshot_q[previous_bank][57], snapshot_q[previous_bank]};
  wire signed [58:0] block_difference_i = $signed({sum_i_i[57], sum_i_i}) - (previous_i <<< 1);
  wire signed [58:0] block_difference_q = $signed({sum_q_i[57], sum_q_i}) - (previous_q <<< 1);

  always @(posedge clk) begin
    if (!rst_n || arm_i) begin
      snapshot_valid <= 0;
      snapshot_exponent[0] <= 0;
      snapshot_exponent[1] <= 0;
      capture_block_valid <= 0;
      capture_block_i <= 0;
      capture_block_q <= 0;
    end else if (check_i) begin
      snapshot_valid[check_exponent_i[0]] <= 1;
      snapshot_exponent[check_exponent_i[0]] <= check_exponent_i;
      capture_block_valid <= snapshot_valid[previous_bank] &&
                             (check_exponent_i > 5'd2) &&
                             (snapshot_exponent[previous_bank] == check_exponent_i - 5'd1);
      capture_block_i <= block_difference_i;
      capture_block_q <= block_difference_q;
    end
  end

  always @(posedge clk) begin
    if (!rst_n) begin
      captured <= 0;
      snapshot_i[0] <= 0;
      snapshot_i[1] <= 0;
      snapshot_q[0] <= 0;
      snapshot_q[1] <= 0;
      capture_diff_i <= 0;
      capture_diff_q <= 0;
      capture_exponent <= 0;
    end else if (check_i) begin
      captured <= 1;
      snapshot_i[check_exponent_i[0]] <= sum_i_i;
      snapshot_q[check_exponent_i[0]] <= sum_q_i;
      capture_diff_i <= diff_i_i;
      capture_diff_q <= diff_q_i;
      capture_exponent <= check_exponent_i;
    end else begin
      captured <= 0;
    end
  end

  wire [57:0] folded_sum_i = capture_sum_i ^ {58{capture_sum_i[57]}};
  wire [57:0] folded_sum_q = capture_sum_q ^ {58{capture_sum_q[57]}};
  wire [57:0] folded_diff_i = capture_diff_i ^ {58{capture_diff_i[57]}};
  wire [57:0] folded_diff_q = capture_diff_q ^ {58{capture_diff_q[57]}};

  wire [58:0] signal_sum = folded_sum_i + folded_sum_q
                         + {57'd0, capture_sum_i[57]} + {57'd0, capture_sum_q[57]};
  wire [58:0] noise_sum = folded_diff_i + folded_diff_q
                        + {57'd0, capture_diff_i[57]} + {57'd0, capture_diff_q[57]};
  wire [58:0] folded_block_i = capture_block_i ^ {59{capture_block_i[58]}};
  wire [58:0] folded_block_q = capture_block_q ^ {59{capture_block_q[58]}};
  wire [59:0] block_sum = {1'b0, folded_block_i} + {1'b0, folded_block_q}
                       + {59'd0, capture_block_i[58]} + {59'd0, capture_block_q[58]};

  always @(posedge clk) begin
    if (!rst_n) begin
      valid_o <= 0;
      signal_magnitude_o <= 0;
      noise_magnitude_o <= 0;
      block_magnitude_o <= 0;
      block_valid_o <= 0;
      exponent_o <= 0;
    end else if (captured) begin
      valid_o <= 1;
      signal_magnitude_o <= signal_sum;
      noise_magnitude_o <= noise_sum;
      block_magnitude_o <= block_sum;
      block_valid_o <= capture_block_valid & ~arm_i;
      exponent_o <= capture_exponent;
    end else begin
      valid_o <= 0;
      block_valid_o <= 0;
    end
  end

endmodule
