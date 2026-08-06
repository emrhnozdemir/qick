`timescale 1ns / 1ps

module estop_split (
  input wire clk,
  input wire rst_n,

  input wire arm_i,
  input wire en_i,
  input wire fold_i,
  input wire [31:0] n_i,
  input wire [31:0] n_min_i,
  input wire [3:0] m_i,
  input wire [1:0] dens_i,
  input wire [2:0] confirm_i,

  input wire signed [63:0] d_i_i,
  input wire signed [63:0] d_q_i,
  input wire signed [63:0] s_i_i,
  input wire signed [63:0] s_q_i,

  output reg stop_o,
  output reg [31:0] np_n_o,
  output reg [4:0] j_o,
  output reg [1:0] midx_o,
  output reg pass_o,
  output reg sat_o,
  output wire at_d1_o
);

  wire [31:0] ckpt_w;
  wire [4:0] j_w;
  wire [1:0] midx_w;

  wire at_ckpt = fold_i & (n_i == ckpt_w);

  ckpt_gen u_ckpt_gen (
    .clk    (clk),
    .rst_n  (rst_n),
    .arm_i  (arm_i),
    .dens_i (dens_i),
    .hit_i  (at_ckpt),
    .ckpt_o (ckpt_w),
    .j_o    (j_w),
    .midx_o (midx_w)
  );

  (* mark_debug = "true" *) reg [3:0] m_r;
  reg [31:0] nmin_r;
  reg [2:0] conf_r;

  always @(posedge clk) begin
    if (!rst_n) begin
      m_r <= 4'd0;
      nmin_r <= 32'd0;
      conf_r <= 3'd0;
    end else if (arm_i) begin
      m_r <= m_i;
      nmin_r <= n_min_i;
      conf_r <= confirm_i;
    end else begin
      m_r <= m_r;
      nmin_r <= nmin_r;
      conf_r <= conf_r;
    end
  end

  reg at0;
  reg signed [63:0] c_di;
  reg signed [63:0] c_dq;
  reg signed [63:0] c_si;
  reg signed [63:0] c_sq;
  reg [31:0] c_n;
  reg [4:0] c_j;
  reg [1:0] c_midx;

  always @(posedge clk) begin
    if (!rst_n) begin
      at0 <= 1'b0;
      c_di <= {64{1'b0}};
      c_dq <= {64{1'b0}};
      c_si <= {64{1'b0}};
      c_sq <= {64{1'b0}};
      c_n <= 32'd0;
      c_j <= 5'd0;
      c_midx <= 2'd0;
    end else if (at_ckpt) begin
      at0 <= 1'b1;
      c_di <= d_i_i;
      c_dq <= d_q_i;
      c_si <= s_i_i;
      c_sq <= s_q_i;
      c_n <= ckpt_w;
      c_j <= j_w;
      c_midx <= midx_w;
    end else begin
      at0 <= 1'b0;
      c_di <= c_di;
      c_dq <= c_dq;
      c_si <= c_si;
      c_sq <= c_sq;
      c_n <= c_n;
      c_j <= c_j;
      c_midx <= c_midx;
    end
  end

  assign at_d1_o = at0;

  wire [63:0] a_di;
  wire [63:0] a_dq;
  wire [63:0] a_si;
  wire [63:0] a_sq;

  abs_value #(.W(64)) u_abs_di (
    .a_i (c_di),
    .y_o (a_di)
  );

  abs_value #(.W(64)) u_abs_dq (
    .a_i (c_dq),
    .y_o (a_dq)
  );

  abs_value #(.W(64)) u_abs_si (
    .a_i (c_si),
    .y_o (a_si)
  );

  abs_value #(.W(64)) u_abs_sq (
    .a_i (c_sq),
    .y_o (a_sq)
  );

  reg at1;
  (* mark_debug = "true" *) reg [63:0] lhs_r;
  (* mark_debug = "true" *) reg [63:0] rhs_r;
  reg [31:0] n1;
  reg [4:0] j1;
  reg [1:0] midx1;

  always @(posedge clk) begin
    if (!rst_n) begin
      at1 <= 1'b0;
      lhs_r <= {64{1'b0}};
      rhs_r <= {64{1'b0}};
      n1 <= 32'd0;
      j1 <= 5'd0;
      midx1 <= 2'd0;
    end else if (at0) begin
      at1 <= 1'b1;
      lhs_r <= a_di + a_dq;
      rhs_r <= a_si + a_sq;
      n1 <= c_n;
      j1 <= c_j;
      midx1 <= c_midx;
    end else begin
      at1 <= 1'b0;
      lhs_r <= lhs_r;
      rhs_r <= rhs_r;
      n1 <= n1;
      j1 <= j1;
      midx1 <= midx1;
    end
  end

  wire pass_w = (lhs_r <= (rhs_r >> m_r));
  wire elig_w = (n1 >= nmin_r);

  reg [2:0] streak;

  wire [2:0] cm1 = (conf_r == 3'd0) ? 3'd0 : (conf_r - 3'd1);
  wire confirmed = pass_w & (streak >= cm1);

  wire [5:0] mag_l_exp;
  wire [3:0] mag_l_mant;
  wire [5:0] mag_r_exp;
  wire [3:0] mag_r_mant;

  mag_class u_mag_l (
    .v_i    (lhs_r),
    .exp_o  (mag_l_exp),
    .mant_o (mag_l_mant)
  );

  mag_class u_mag_r (
    .v_i    (rhs_r),
    .exp_o  (mag_r_exp),
    .mant_o (mag_r_mant)
  );

  wire signed [10:0] rcur = {1'b0, mag_l_exp, mag_l_mant} - {1'b0, mag_r_exp, mag_r_mant};

  reg signed [10:0] rprev;
  reg ndprev;

  wire nondec = (rcur >= rprev);

  always @(posedge clk) begin
    if (!rst_n) begin
      stop_o <= 1'b0;
      np_n_o <= 32'd0;
      j_o <= 5'd0;
      midx_o <= 2'd0;
      pass_o <= 1'b0;
      sat_o <= 1'b0;
      streak <= 3'd0;
      rprev <= 11'sd1023;
      ndprev <= 1'b0;
    end else if (arm_i) begin
      stop_o <= 1'b0;
      np_n_o <= np_n_o;
      j_o <= j_o;
      midx_o <= midx_o;
      pass_o <= 1'b0;
      sat_o <= 1'b0;
      streak <= 3'd0;
      rprev <= 11'sd1023;
      ndprev <= 1'b0;
    end else if (at1) begin
      stop_o <= en_i & confirmed & elig_w;
      np_n_o <= n1;
      j_o <= j1;
      midx_o <= midx1;
      pass_o <= pass_w;
      streak <= pass_w ? ((streak == 3'd7) ? 3'd7 : (streak + 3'd1)) : 3'd0;
      if (~pass_w & elig_w) begin
        sat_o <= sat_o | (nondec & ndprev);
        rprev <= rcur;
        ndprev <= nondec;
      end else begin
        sat_o <= sat_o;
        rprev <= rprev;
        ndprev <= ndprev;
      end
    end else begin
      stop_o <= 1'b0;
      np_n_o <= np_n_o;
      j_o <= j_o;
      midx_o <= midx_o;
      pass_o <= pass_o;
      sat_o <= sat_o;
      streak <= streak;
      rprev <= rprev;
      ndprev <= ndprev;
    end
  end

endmodule
