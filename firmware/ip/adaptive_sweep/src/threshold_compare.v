`timescale 1ns / 1ps

module threshold_compare(
  input clk,
  input rst_n,

  input arm_i,
  input enable_i,
  input [15:0] threshold_i,
  input block_en_i,
  input [31:0] block_tol_i,
  input [31:0] n_min_i,
  input [2:0] confirm_i,

  input valid_i,
  input [58:0] signal_magnitude_i,
  input [58:0] noise_magnitude_i,
  input [59:0] block_magnitude_i,
  input block_valid_i,
  input [4:0] exponent_i,
  input power_i,

  output reg stop_o,
  output reg [4:0] stop_exponent_o,
  output reg saturated_o,
  output verdict_valid_o,
  output verdict_passed_o,
  output verdict_power_o,
  output [4:0] verdict_exponent_o
);

  reg stage1_valid;
  reg stage2_valid;
  reg stage3_valid;
  reg [19:0] noise_chunk0;
  reg [19:0] noise_chunk1;
  reg [18:0] noise_chunk2;
  reg [58:0] stage1_signal;
  reg [4:0] stage1_exponent;
  reg stage1_power;
  reg stage1_block_pass;
  reg stage2_block_pass;
  reg stage3_block_pass;
  reg stage4_block_pass;

  wire [63:0] block_limit = {32'd0, block_tol_i} << (exponent_i - 5'd1);
  always @(posedge clk) begin
    if (!rst_n || arm_i) begin
      stage1_block_pass <= 0;
      stage2_block_pass <= 0;
      stage3_block_pass <= 0;
      stage4_block_pass <= 0;
    end else begin
      if (valid_i)
        stage1_block_pass <= block_valid_i && ({4'd0, block_magnitude_i} <= block_limit);
      if (stage1_valid) stage2_block_pass <= stage1_block_pass;
      if (stage2_valid) stage3_block_pass <= stage2_block_pass;
      if (stage3_valid) stage4_block_pass <= stage3_block_pass;
    end
  end

  always @(posedge clk) begin
    if (!rst_n || arm_i) begin
      stage1_valid <= 0;
      noise_chunk0 <= 0;
      noise_chunk1 <= 0;
      noise_chunk2 <= 0;
      stage1_signal <= 0;
      stage1_exponent <= 0;
      stage1_power <= 0;
    end else if (valid_i) begin
      stage1_valid <= 1;
      noise_chunk0 <= noise_magnitude_i[19:0];
      noise_chunk1 <= noise_magnitude_i[39:20];
      noise_chunk2 <= noise_magnitude_i[58:40];
      stage1_signal <= signal_magnitude_i;
      stage1_exponent <= exponent_i;
      stage1_power <= power_i;
    end else begin
      stage1_valid <= 0;
    end
  end

  (* use_dsp = "yes" *) reg [35:0] product0;
  (* use_dsp = "yes" *) reg [35:0] product1;
  (* use_dsp = "yes" *) reg [34:0] product2;
  reg [58:0] stage2_signal;
  reg [4:0] stage2_exponent;
  reg stage2_power;

  always @(posedge clk) begin
    if (!rst_n || arm_i) begin
      stage2_valid <= 0;
      product0 <= 0;
      product1 <= 0;
      product2 <= 0;
      stage2_signal <= 0;
      stage2_exponent <= 0;
      stage2_power <= 0;
    end else if (stage1_valid) begin
      stage2_valid <= 1;
      product0 <= noise_chunk0 * threshold_i;
      product1 <= noise_chunk1 * threshold_i;
      product2 <= noise_chunk2 * threshold_i;
      stage2_signal <= stage1_signal;
      stage2_exponent <= stage1_exponent;
      stage2_power <= stage1_power;
    end else begin
      stage2_valid <= 0;
    end
  end

  wire [74:0] scaled_sum = {39'd0, product0}
                         + {19'd0, product1, 20'd0}
                         + {product2, 40'd0};

  reg [74:0] scaled_noise;
  reg [58:0] stage3_signal;
  reg [4:0] stage3_exponent;
  reg stage3_power;

  always @(posedge clk) begin
    if (!rst_n || arm_i) begin
      stage3_valid <= 0;
      scaled_noise <= 0;
      stage3_signal <= 0;
      stage3_exponent <= 0;
      stage3_power <= 0;
    end else if (stage2_valid) begin
      stage3_valid <= 1;
      scaled_noise <= scaled_sum;
      stage3_signal <= stage2_signal;
      stage3_exponent <= stage2_exponent;
      stage3_power <= stage2_power;
    end else begin
      stage3_valid <= 0;
    end
  end

  wire signed [75:0] margin_next = $signed({17'd0, stage3_signal})
                                 - $signed({1'b0, scaled_noise});

  reg stage4_valid;
  reg signed [75:0] margin;
  reg [4:0] stage4_exponent;
  reg stage4_power;

  always @(posedge clk) begin
    if (!rst_n || arm_i) begin
      stage4_valid <= 0;
      margin <= 0;
      stage4_exponent <= 0;
      stage4_power <= 0;
    end else if (stage3_valid) begin
      stage4_valid <= 1;
      margin <= margin_next;
      stage4_exponent <= stage3_exponent;
      stage4_power <= stage3_power;
    end else begin
      stage4_valid <= 0;
    end
  end

  wire odd_even_pass = ~margin[75];
  wire passed = odd_even_pass & (~block_en_i | stage4_block_pass);
  assign verdict_valid_o = stage4_valid & ~arm_i;
  assign verdict_passed_o = passed;
  assign verdict_power_o = stage4_power;
  assign verdict_exponent_o = stage4_exponent;
  wire eligible = ((32'd1 << stage4_exponent) >= n_min_i);

  reg [2:0] pass_streak;

  wire [2:0] confirm_minus_one = (confirm_i == 0) ? 3'd0 : (confirm_i - 3'd1);
  wire confirmed = passed & (pass_streak >= confirm_minus_one);

  reg signed [75:0] previous_margin;
  reg previous_not_improving;

  wire not_improving = (margin <= previous_margin);

  always @(posedge clk) begin
    if (!rst_n) begin
      stop_o <= 0;
      stop_exponent_o <= 0;
      saturated_o <= 0;
      pass_streak <= 0;
      previous_margin <= {1'b1, 75'd0};
      previous_not_improving <= 0;
    end else if (arm_i) begin
      stop_o <= 0;
      saturated_o <= 0;
      pass_streak <= 0;
      previous_margin <= {1'b1, 75'd0};
      previous_not_improving <= 0;
    end else if (stage4_valid) begin
      stop_o <= enable_i & confirmed & eligible;
      stop_exponent_o <= stage4_exponent;
      pass_streak <= passed ? ((pass_streak == 3'd7) ? 3'd7 : (pass_streak + 3'd1)) : 3'd0;
      if (stage4_power & ~odd_even_pass & eligible) begin
        saturated_o <= saturated_o | (not_improving & previous_not_improving);
        previous_margin <= margin;
        previous_not_improving <= not_improving;
      end
    end else begin
      stop_o <= 0;
    end
  end

endmodule
