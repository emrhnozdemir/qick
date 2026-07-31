`timescale 1ns / 1ps

module power_macc (
  input wire clk,
  input wire rst_n,

  input wire start_i,
  input wire signed [63:0] i_i,
  input wire signed [63:0] q_i,

  (* mark_debug = "true" *) output reg [127:0] power_o,
  (* mark_debug = "true" *) output reg valid_o
);

  reg ld0;
  reg ld1;

  always @(posedge clk) begin
    if (!rst_n) begin
      ld0 <= 1'b0;
      ld1 <= 1'b0;
    end else begin
      ld0 <= start_i;
      ld1 <= ld0;
    end
  end

  wire signed [63:0] sq_in = ld0 ? i_i : q_i;
  wire sq_in_v = ld0 | ld1;
  wire sq_in_f = ld0;

  reg signed [17:0] c0;
  reg signed [17:0] c1;
  reg signed [17:0] c2;
  reg signed [17:0] c3;

  always @(posedge clk) begin
    if (!rst_n) begin
      c0 <= {18{1'b0}};
      c1 <= {18{1'b0}};
      c2 <= {18{1'b0}};
      c3 <= {18{1'b0}};
    end else begin
      c0 <= {2'b00, sq_in[15:0]};
      c1 <= {2'b00, sq_in[31:16]};
      c2 <= {2'b00, sq_in[47:32]};
      c3 <= {{2{sq_in[63]}}, sq_in[63:48]};
    end
  end

  reg signed [35:0] p00;
  reg signed [35:0] p10;
  reg signed [35:0] p11;
  reg signed [35:0] p20;
  reg signed [35:0] p21;
  reg signed [35:0] p22;
  reg signed [35:0] p30;
  reg signed [35:0] p31;
  reg signed [35:0] p32;
  reg signed [35:0] p33;

  always @(posedge clk) begin
    if (!rst_n) begin
      p00 <= {36{1'b0}};
      p10 <= {36{1'b0}};
      p11 <= {36{1'b0}};
      p20 <= {36{1'b0}};
      p21 <= {36{1'b0}};
      p22 <= {36{1'b0}};
      p30 <= {36{1'b0}};
      p31 <= {36{1'b0}};
      p32 <= {36{1'b0}};
      p33 <= {36{1'b0}};
    end else begin
      p00 <= c0 * c0;
      p10 <= c1 * c0;
      p11 <= c1 * c1;
      p20 <= c2 * c0;
      p21 <= c2 * c1;
      p22 <= c2 * c2;
      p30 <= c3 * c0;
      p31 <= c3 * c1;
      p32 <= c3 * c2;
      p33 <= c3 * c3;
    end
  end

  reg signed [37:0] s0;
  reg signed [37:0] s1;
  reg signed [37:0] s2;
  reg signed [37:0] s3;
  reg signed [37:0] s4;
  reg signed [37:0] s5;
  reg signed [37:0] s6;

  always @(posedge clk) begin
    if (!rst_n) begin
      s0 <= {38{1'b0}};
      s1 <= {38{1'b0}};
      s2 <= {38{1'b0}};
      s3 <= {38{1'b0}};
      s4 <= {38{1'b0}};
      s5 <= {38{1'b0}};
      s6 <= {38{1'b0}};
    end else begin
      s0 <= p00;
      s1 <= p10 <<< 1;
      s2 <= p11 + (p20 <<< 1);
      s3 <= (p21 + p30) <<< 1;
      s4 <= p22 + (p31 <<< 1);
      s5 <= p32 <<< 1;
      s6 <= p33;
    end
  end

  wire signed [127:0] w0 = {{90{s0[37]}}, s0};
  wire signed [127:0] w1 = {{90{s1[37]}}, s1} <<< 16;
  wire signed [127:0] w2 = {{90{s2[37]}}, s2} <<< 32;
  wire signed [127:0] w3 = {{90{s3[37]}}, s3} <<< 48;
  wire signed [127:0] w4 = {{90{s4[37]}}, s4} <<< 64;
  wire signed [127:0] w5 = {{90{s5[37]}}, s5} <<< 80;
  wire signed [127:0] w6 = {{90{s6[37]}}, s6} <<< 96;

  reg signed [127:0] t0;
  reg signed [127:0] t1;
  reg signed [127:0] t2;
  reg signed [127:0] t3;

  always @(posedge clk) begin
    if (!rst_n) begin
      t0 <= {128{1'b0}};
      t1 <= {128{1'b0}};
      t2 <= {128{1'b0}};
      t3 <= {128{1'b0}};
    end else begin
      t0 <= w0 + w1;
      t1 <= w2 + w3;
      t2 <= w4 + w5;
      t3 <= w6;
    end
  end

  reg signed [127:0] u0;
  reg signed [127:0] u1;

  always @(posedge clk) begin
    if (!rst_n) begin
      u0 <= {128{1'b0}};
      u1 <= {128{1'b0}};
    end else begin
      u0 <= t0 + t1;
      u1 <= t2 + t3;
    end
  end

  reg signed [127:0] sq_res;

  always @(posedge clk) begin
    if (!rst_n)
      sq_res <= {128{1'b0}};
    else
      sq_res <= u0 + u1;
  end

  reg [5:0] v_pipe;
  reg [5:0] f_pipe;

  always @(posedge clk) begin
    if (!rst_n) begin
      v_pipe <= 6'd0;
      f_pipe <= 6'd0;
    end else begin
      v_pipe <= {v_pipe[4:0], sq_in_v};
      f_pipe <= {f_pipe[4:0], sq_in_f};
    end
  end

  (* mark_debug = "true" *) reg [127:0] power_acc;
  reg acc_last;

  always @(posedge clk) begin
    if (!rst_n) begin
      power_acc <= {128{1'b0}};
      acc_last <= 1'b0;
      power_o <= {128{1'b0}};
      valid_o <= 1'b0;
    end else begin
      if (v_pipe[5] & f_pipe[5])
        power_acc <= sq_res;
      else if (v_pipe[5])
        power_acc <= power_acc + sq_res;
      else
        power_acc <= power_acc;
      acc_last <= v_pipe[5] & ~f_pipe[5];
      power_o <= power_acc;
      valid_o <= acc_last;
    end
  end

  (* mark_debug = "true" *) reg start_dbg;
  (* mark_debug = "true" *) reg sq_in_v_dbg;
  (* mark_debug = "true" *) reg sq_in_f_dbg;
  (* mark_debug = "true" *) reg [5:0] v_pipe_dbg;
  (* mark_debug = "true" *) reg [5:0] f_pipe_dbg;
  (* mark_debug = "true" *) reg signed [127:0] sq_res_dbg;
  (* mark_debug = "true" *) reg acc_last_dbg;
  always @(posedge clk) begin
    if (!rst_n) begin
      start_dbg <= 1'b0;
      sq_in_v_dbg <= 1'b0;
      sq_in_f_dbg <= 1'b0;
      v_pipe_dbg <= 6'd0;
      f_pipe_dbg <= 6'd0;
      sq_res_dbg <= {128{1'b0}};
      acc_last_dbg <= 1'b0;
    end else begin
      start_dbg <= start_i;
      sq_in_v_dbg <= sq_in_v;
      sq_in_f_dbg <= sq_in_f;
      v_pipe_dbg <= v_pipe;
      f_pipe_dbg <= f_pipe;
      sq_res_dbg <= sq_res;
      acc_last_dbg <= acc_last;
    end
  end

endmodule
