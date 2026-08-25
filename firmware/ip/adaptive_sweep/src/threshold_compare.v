`timescale 1ns / 1ps

module threshold_compare(
  input clk,
  input rst_n,

  input arm_i,
  input enable_i,
  input [15:0] threshold_i,
  input [31:0] n_min_i,
  input [2:0] confirm_i,

  input valid_i,
  input [58:0] signal_magnitude_i,
  input [58:0] noise_magnitude_i,
  input [4:0] exponent_i,

  (* MARK_DEBUG = "TRUE" *) output reg stop_o,
  (* MARK_DEBUG = "TRUE" *) output reg [4:0] stop_exponent_o,
  (* MARK_DEBUG = "TRUE" *) output reg saturated_o
);

  (* MARK_DEBUG = "TRUE" *) reg [15:0] threshold;
  reg [31:0] n_min;
  reg [2:0] confirm;

  always @(posedge clk) begin
    if (!rst_n) begin
      threshold <= 0;
      n_min <= 0;
      confirm <= 0;
    end else if (arm_i) begin
      threshold <= threshold_i;
      n_min <= n_min_i;
      confirm <= confirm_i;
    end
  end

  reg stage1_valid;
  reg [19:0] noise_chunk0;
  reg [19:0] noise_chunk1;
  reg [18:0] noise_chunk2;
  reg [58:0] stage1_signal;
  reg [4:0] stage1_exponent;

  always @(posedge clk) begin
    if (!rst_n) begin
      stage1_valid <= 0;
      noise_chunk0 <= 0;
      noise_chunk1 <= 0;
      noise_chunk2 <= 0;
      stage1_signal <= 0;
      stage1_exponent <= 0;
    end else if (valid_i) begin
      stage1_valid <= 1;
      noise_chunk0 <= noise_magnitude_i[19:0];
      noise_chunk1 <= noise_magnitude_i[39:20];
      noise_chunk2 <= noise_magnitude_i[58:40];
      stage1_signal <= signal_magnitude_i;
      stage1_exponent <= exponent_i;
    end else begin
      stage1_valid <= 0;
    end
  end

  reg stage2_valid;
  (* use_dsp = "yes" *) reg [35:0] product0;
  (* use_dsp = "yes" *) reg [35:0] product1;
  (* use_dsp = "yes" *) reg [34:0] product2;
  reg [58:0] stage2_signal;
  reg [4:0] stage2_exponent;

  always @(posedge clk) begin
    if (!rst_n) begin
      stage2_valid <= 0;
      product0 <= 0;
      product1 <= 0;
      product2 <= 0;
      stage2_signal <= 0;
      stage2_exponent <= 0;
    end else if (stage1_valid) begin
      stage2_valid <= 1;
      product0 <= noise_chunk0 * threshold;
      product1 <= noise_chunk1 * threshold;
      product2 <= noise_chunk2 * threshold;
      stage2_signal <= stage1_signal;
      stage2_exponent <= stage1_exponent;
    end else begin
      stage2_valid <= 0;
    end
  end

  wire [74:0] scaled_sum = {39'd0, product0}
                         + {19'd0, product1, 20'd0}
                         + {product2, 40'd0};

  reg stage3_valid;
  (* MARK_DEBUG = "TRUE" *) reg [74:0] scaled_noise;
  reg [58:0] stage3_signal;
  reg [4:0] stage3_exponent;

  always @(posedge clk) begin
    if (!rst_n) begin
      stage3_valid <= 0;
      scaled_noise <= 0;
      stage3_signal <= 0;
      stage3_exponent <= 0;
    end else if (stage2_valid) begin
      stage3_valid <= 1;
      scaled_noise <= scaled_sum;
      stage3_signal <= stage2_signal;
      stage3_exponent <= stage2_exponent;
    end else begin
      stage3_valid <= 0;
    end
  end

  wire signed [75:0] margin_next = $signed({17'd0, stage3_signal})
                                 - $signed({1'b0, scaled_noise});

  reg stage4_valid;
  (* MARK_DEBUG = "TRUE" *) reg signed [75:0] margin;
  reg [4:0] stage4_exponent;

  always @(posedge clk) begin
    if (!rst_n) begin
      stage4_valid <= 0;
      margin <= 0;
      stage4_exponent <= 0;
    end else if (stage3_valid) begin
      stage4_valid <= 1;
      margin <= margin_next;
      stage4_exponent <= stage3_exponent;
    end else begin
      stage4_valid <= 0;
    end
  end

  (* MARK_DEBUG = "TRUE" *) wire passed = ~margin[75];
  wire eligible = ((32'd1 << stage4_exponent) >= n_min);

  (* MARK_DEBUG = "TRUE" *) reg [2:0] pass_streak;

  wire [2:0] confirm_minus_one = (confirm == 0) ? 3'd0 : (confirm - 3'd1);
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
      if (~passed & eligible) begin
        saturated_o <= saturated_o | (not_improving & previous_not_improving);
        previous_margin <= margin;
        previous_not_improving <= not_improving;
      end
    end else begin
      stop_o <= 0;
    end
  end

endmodule
