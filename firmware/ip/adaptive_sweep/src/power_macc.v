`timescale 1ns / 1ps

module power_macc (
  input wire clk,
  input wire rst_n,

  input wire start_i,
  input wire signed [31:0] i_i,
  input wire signed [31:0] q_i,

  (* mark_debug = "true" *) output reg [63:0] power_o,
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

  wire signed [31:0] sq_in = ld0 ? i_i : q_i;
  wire sq_in_v = ld0 | ld1;
  wire sq_in_f = ld0;

  reg signed [17:0] c0;
  reg signed [17:0] c1;

  always @(posedge clk) begin
    if (!rst_n) begin
      c0 <= {18{1'b0}};
      c1 <= {18{1'b0}};
    end else begin
      c0 <= {2'b00, sq_in[15:0]};
      c1 <= {{2{sq_in[31]}}, sq_in[31:16]};
    end
  end

  reg signed [35:0] p00;
  reg signed [35:0] p10;
  reg signed [35:0] p11;

  always @(posedge clk) begin
    if (!rst_n) begin
      p00 <= {36{1'b0}};
      p10 <= {36{1'b0}};
      p11 <= {36{1'b0}};
    end else begin
      p00 <= c0 * c0;
      p10 <= c1 * c0;
      p11 <= c1 * c1;
    end
  end

  reg signed [36:0] s0;
  reg signed [36:0] s1;
  reg signed [36:0] s2;

  always @(posedge clk) begin
    if (!rst_n) begin
      s0 <= {37{1'b0}};
      s1 <= {37{1'b0}};
      s2 <= {37{1'b0}};
    end else begin
      s0 <= p00;
      s1 <= p10 <<< 1;
      s2 <= p11;
    end
  end

  wire signed [63:0] w0 = {{27{s0[36]}}, s0};
  wire signed [63:0] w1 = {{27{s1[36]}}, s1} <<< 16;
  wire signed [63:0] w2 = {{27{s2[36]}}, s2} <<< 32;

  reg signed [63:0] sq_res;

  always @(posedge clk) begin
    if (!rst_n)
      sq_res <= {64{1'b0}};
    else
      sq_res <= w0 + w1 + w2;
  end

  reg [3:0] v_pipe;
  reg [3:0] f_pipe;

  always @(posedge clk) begin
    if (!rst_n) begin
      v_pipe <= 4'd0;
      f_pipe <= 4'd0;
    end else begin
      v_pipe <= {v_pipe[2:0], sq_in_v};
      f_pipe <= {f_pipe[2:0], sq_in_f};
    end
  end

  (* mark_debug = "true" *) reg [63:0] power_acc;
  reg acc_last;

  always @(posedge clk) begin
    if (!rst_n) begin
      power_acc <= {64{1'b0}};
      acc_last <= 1'b0;
      power_o <= {64{1'b0}};
      valid_o <= 1'b0;
    end else begin
      if (v_pipe[3] & f_pipe[3])
        power_acc <= sq_res;
      else if (v_pipe[3])
        power_acc <= power_acc + sq_res;
      else
        power_acc <= power_acc;
      acc_last <= v_pipe[3] & ~f_pipe[3];
      power_o <= power_acc;
      valid_o <= acc_last;
    end
  end

  (* mark_debug = "true" *) reg start_dbg;
  (* mark_debug = "true" *) reg sq_in_v_dbg;
  (* mark_debug = "true" *) reg sq_in_f_dbg;
  (* mark_debug = "true" *) reg [3:0] v_pipe_dbg;
  (* mark_debug = "true" *) reg [3:0] f_pipe_dbg;
  (* mark_debug = "true" *) reg signed [63:0] sq_res_dbg;
  (* mark_debug = "true" *) reg acc_last_dbg;
  always @(posedge clk) begin
    if (!rst_n) begin
      start_dbg <= 1'b0;
      sq_in_v_dbg <= 1'b0;
      sq_in_f_dbg <= 1'b0;
      v_pipe_dbg <= 4'd0;
      f_pipe_dbg <= 4'd0;
      sq_res_dbg <= {64{1'b0}};
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
