`timescale 1ns / 1ps

module gm_divider (
  input wire clk,
  input wire rst_n,

  input wire start_i,
  input wire signed [63:0] num_i,
  input wire [31:0] den_i,
  input wire [5:0] kp1_i,
  input wire [53:0] mag_i,
  input wire [4:0] sft_i,

  output wire busy_o,
  output reg done_o,
  output reg signed [31:0] q_o
);

  wire [66:0] num_x2 = {{2{num_i[63]}}, num_i, 1'b0};
  wire [66:0] den_lo = {35'd0, den_i};
  wire [66:0] den_hi = {2'd0, den_i, 33'd0};
  wire [66:0] a_init = num_x2 + den_lo + den_hi;

  reg v0;
  reg [65:0] a_r;
  reg [5:0] kp1_r;
  reg [53:0] mag_r0;
  reg [4:0] sft_r0;

  reg v1;
  reg [51:0] t_r;
  reg [53:0] mag_r1;
  reg [4:0] sft_r1;

  reg v2;
  reg [78:0] pp0_r;
  reg [78:0] pp1_r;
  reg [4:0] sft_r2;

  reg v3;
  reg [105:0] prod_r;
  reg [4:0] sft_r3;

  reg v4;
  reg [33:0] q34_r;

  wire [65:0] t_sh = a_r >> kp1_r;
  wire [53:0] hi54 = prod_r[105:52];
  wire [53:0] hi_sh = hi54 >> sft_r3;
  wire signed [34:0] qs = {1'b0, q34_r} - 35'sd4294967296;

  assign busy_o = v0 | v1 | v2 | v3 | v4 | done_o;

  always @(posedge clk) begin
    if (!rst_n) begin
      v0 <= 1'b0;
      a_r <= 66'd0;
      kp1_r <= 6'd0;
      mag_r0 <= 54'd0;
      sft_r0 <= 5'd0;
      v1 <= 1'b0;
      t_r <= 52'd0;
      mag_r1 <= 54'd0;
      sft_r1 <= 5'd0;
      v2 <= 1'b0;
      pp0_r <= 79'd0;
      pp1_r <= 79'd0;
      sft_r2 <= 5'd0;
      v3 <= 1'b0;
      prod_r <= 106'd0;
      sft_r3 <= 5'd0;
      v4 <= 1'b0;
      q34_r <= 34'd0;
      done_o <= 1'b0;
      q_o <= 32'd0;
    end else begin
      v0 <= start_i;
      if (start_i) begin
        a_r <= a_init[65:0];
        kp1_r <= kp1_i;
        mag_r0 <= mag_i;
        sft_r0 <= sft_i;
      end else begin
        a_r <= a_r;
        kp1_r <= kp1_r;
        mag_r0 <= mag_r0;
        sft_r0 <= sft_r0;
      end

      v1 <= v0;
      if (v0) begin
        t_r <= t_sh[51:0];
        mag_r1 <= mag_r0;
        sft_r1 <= sft_r0;
      end else begin
        t_r <= t_r;
        mag_r1 <= mag_r1;
        sft_r1 <= sft_r1;
      end

      v2 <= v1;
      if (v1) begin
        pp0_r <= t_r * mag_r1[26:0];
        pp1_r <= t_r * mag_r1[53:27];
        sft_r2 <= sft_r1;
      end else begin
        pp0_r <= pp0_r;
        pp1_r <= pp1_r;
        sft_r2 <= sft_r2;
      end

      v3 <= v2;
      if (v2) begin
        prod_r <= {pp1_r, 27'd0} + {27'd0, pp0_r};
        sft_r3 <= sft_r2;
      end else begin
        prod_r <= prod_r;
        sft_r3 <= sft_r3;
      end

      v4 <= v3;
      if (v3) begin
        q34_r <= hi_sh[33:0];
      end else begin
        q34_r <= q34_r;
      end

      done_o <= v4;
      if (v4) begin
        q_o <= qs[31:0];
      end else begin
        q_o <= q_o;
      end
    end
  end

endmodule
