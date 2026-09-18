`timescale 1ns / 1ps

// Start at a passing power of two N; require confirm_i total passes at
// N, N+2, ... and return the saved N-sample sum. All even checkpoints are
// evaluated speculatively so continuous AXIS traffic cannot skip a recheck.
module short_confirmation(
  input clk,
  input rst_n,
  input arm_i,
  input enable_i,
  input block_en_i,
  input [15:0] threshold_i,
  input [31:0] n_min_i,
  input [2:0] confirm_i,
  input check_i,
  input power_check_i,
  input [4:0] power_exponent_i,
  input [31:0] sample_count_i,
  input signed [57:0] sum_i_i,
  input signed [57:0] sum_q_i,
  input signed [57:0] diff_i_i,
  input signed [57:0] diff_q_i,
  output reg stop_o,
  output reg [4:0] stop_exponent_o,
  output reg signed [57:0] snapshot_i_o,
  output reg signed [57:0] snapshot_q_o
);
  reg enabled;
  reg [31:0] n_min;
  reg [2:0] required_passes;
  always @(posedge clk) begin
    if (!rst_n) begin
      enabled <= 0;
      n_min <= 0;
      required_passes <= 1;
    end else if (arm_i) begin
      // The optional half-window guard is defined only at powers of two.
      // Unsupported raw CTRL combinations fall back to the full cap.
      enabled <= enable_i & ~block_en_i;
      n_min <= n_min_i;
      required_passes <= (confirm_i == 0) ? 3'd1 : confirm_i;
    end
  end

  function [57:0] abs58;
    input signed [57:0] value;
    begin abs58 = value[57] ? (~value + 58'd1) : value; end
  endfunction

  reg magnitude_valid;
  reg [58:0] signal_magnitude;
  reg [58:0] noise_magnitude;
  reg [31:0] count_tag [0:4];
  reg [4:0] exponent_tag [0:4];
  reg [4:0] power_tag;
  reg [4:0] valid_tag;
  reg signed [57:0] sum_bank_i [0:1];
  reg signed [57:0] sum_bank_q [0:1];
  integer k;
  wire capture = enabled & check_i;
  always @(posedge clk) begin
    if (!rst_n || arm_i) begin
      magnitude_valid <= 0;
      signal_magnitude <= 0;
      noise_magnitude <= 0;
      power_tag <= 0;
      valid_tag <= 0;
      for (k = 0; k < 5; k = k + 1) begin
        count_tag[k] <= 0;
        exponent_tag[k] <= 0;
      end
      sum_bank_i[0] <= 0;
      sum_bank_i[1] <= 0;
      sum_bank_q[0] <= 0;
      sum_bank_q[1] <= 0;
    end else begin
      magnitude_valid <= capture;
      valid_tag <= {valid_tag[3:0], capture};
      power_tag <= {power_tag[3:0], power_check_i & capture};
      count_tag[0] <= sample_count_i;
      exponent_tag[0] <= power_exponent_i;
      for (k = 1; k < 5; k = k + 1) begin
        count_tag[k] <= count_tag[k-1];
        exponent_tag[k] <= exponent_tag[k-1];
      end
      if (capture) begin
        signal_magnitude <= {1'b0, abs58(sum_i_i)} + {1'b0, abs58(sum_q_i)};
        noise_magnitude <= {1'b0, abs58(diff_i_i)} + {1'b0, abs58(diff_q_i)};
      end
      // Equal-parity powers (4,16 or 8,32) are at least 12 shots apart,
      // longer than the five-cycle verdict latency. Copy into dedicated
      // candidate storage below before these banks can be overwritten.
      if (capture && power_check_i) begin
        sum_bank_i[power_exponent_i[0]] <= sum_i_i;
        sum_bank_q[power_exponent_i[0]] <= sum_q_i;
      end
    end
  end

  wire verdict_valid;
  wire verdict_passed;
  threshold_compare compare(
    .clk(clk), .rst_n(rst_n), .arm_i(arm_i), .enable_i(1'b0),
    .threshold_i(threshold_i), .block_en_i(1'b0), .block_tol_i(32'd0),
    .n_min_i(32'd0), .confirm_i(3'd1), .valid_i(magnitude_valid),
    .signal_magnitude_i(signal_magnitude), .noise_magnitude_i(noise_magnitude),
    .block_magnitude_i(60'd0), .block_valid_i(1'b0), .exponent_i(5'd0),
    .stop_o(), .stop_exponent_o(), .saturated_o(),
    .verdict_valid_o(verdict_valid), .verdict_passed_o(verdict_passed)
  );

  reg pending;
  reg done;
  reg [2:0] passes;
  reg [31:0] next_count;
  always @(posedge clk) begin
    if (!rst_n || arm_i) begin
      pending <= 0;
      done <= 0;
      passes <= 0;
      next_count <= 0;
      stop_o <= 0;
      stop_exponent_o <= 0;
      snapshot_i_o <= 0;
      snapshot_q_o <= 0;
    end else begin
      stop_o <= 0;
      if (enabled && !done && verdict_valid && valid_tag[4]) begin
        if (pending) begin
          if (count_tag[4] == next_count) begin
            if (!verdict_passed) begin
              pending <= 0;
              passes <= 0;
            end else if (passes >= required_passes - 3'd1) begin
              stop_o <= 1;
              pending <= 0;
              done <= 1;
            end else begin
              passes <= passes + 3'd1;
              next_count <= next_count + 32'd2;
            end
          end
        end else if (power_tag[4] && count_tag[4] >= n_min && verdict_passed) begin
          snapshot_i_o <= sum_bank_i[exponent_tag[4][0]];
          snapshot_q_o <= sum_bank_q[exponent_tag[4][0]];
          stop_exponent_o <= exponent_tag[4];
          passes <= 1;
          next_count <= count_tag[4] + 32'd2;
          if (required_passes == 1) begin
            stop_o <= 1;
            done <= 1;
          end else begin
            pending <= 1;
          end
        end
      end
    end
  end
endmodule
