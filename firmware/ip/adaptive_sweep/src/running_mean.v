`timescale 1ns / 1ps

module running_mean #(
  parameter MW = 18,
  parameter RW = 37
) (
  input wire clk,
  input wire rst_n,

  input wire clr,
  input wire en,
  input wire first_i,
  input wire [31:0] n_i,
  input wire signed [MW-1:0] x_i,

  (* mark_debug = "true" *) output reg signed [MW-1:0] mean_o,
  output wire signed [MW-1:0] mean_nxt_o
);

  (* mark_debug = "true" *) reg signed [RW-1:0] rem;

  wire signed [RW-1:0] n_s = {{(RW-32){1'b0}}, n_i};
  wire signed [RW-1:0] two_n = n_s <<< 1;

  wire signed [RW-1:0] x_ext = {{(RW-MW){x_i[MW-1]}}, x_i};
  wire signed [RW-1:0] mean_ext = {{(RW-MW){mean_o[MW-1]}}, mean_o};
  wire signed [RW-1:0] d = x_ext - mean_ext + rem;

  wire signed [RW-1:0] d_m2n = d - two_n;
  wire signed [RW-1:0] d_m1n = d - n_s;
  wire signed [RW-1:0] d_p1n = d + n_s;
  wire signed [RW-1:0] d_p2n = d + two_n;

  wire signed [RW-1:0] rem_step = (!d_m2n[RW-1]) ? d_m2n :
                                  (!d_m1n[RW-1]) ? d_m1n :
                                  (!d[RW-1]) ? d :
                                  (!d_p1n[RW-1]) ? d_p1n : d_p2n;

  wire signed [2:0] q_step = (!d_m2n[RW-1]) ? 3'sd2 :
                             (!d_m1n[RW-1]) ? 3'sd1 :
                             (!d[RW-1]) ? 3'sd0 :
                             (!d_p1n[RW-1]) ? -3'sd1 : -3'sd2;

  wire signed [MW-1:0] mean_step = mean_o + {{(MW-3){q_step[2]}}, q_step};

  wire signed [MW-1:0] mean_upd = first_i ? x_i : mean_step;
  wire signed [RW-1:0] rem_upd = first_i ? {RW{1'b0}} : rem_step;

  assign mean_nxt_o = mean_upd;

  always @(posedge clk) begin
    if (!rst_n) begin
      mean_o <= {MW{1'b0}};
      rem <= {RW{1'b0}};
    end else if (clr) begin
      mean_o <= {MW{1'b0}};
      rem <= {RW{1'b0}};
    end else if (en) begin
      mean_o <= mean_upd;
      rem <= rem_upd;
    end else begin
      mean_o <= mean_o;
      rem <= rem;
    end
  end

  (* mark_debug = "true" *) reg clr_dbg;
  (* mark_debug = "true" *) reg en_dbg;
  (* mark_debug = "true" *) reg first_dbg;
  (* mark_debug = "true" *) reg signed [MW-1:0] x_dbg;
  (* mark_debug = "true" *) reg signed [2:0] q_step_dbg;
  (* mark_debug = "true" *) reg signed [MW-1:0] mean_nxt_dbg;
  always @(posedge clk) begin
    if (!rst_n) begin
      clr_dbg <= 1'b0;
      en_dbg <= 1'b0;
      first_dbg <= 1'b0;
      x_dbg <= {MW{1'b0}};
      q_step_dbg <= 3'd0;
      mean_nxt_dbg <= {MW{1'b0}};
    end else begin
      clr_dbg <= clr;
      en_dbg <= en;
      first_dbg <= first_i;
      x_dbg <= x_i;
      q_step_dbg <= q_step;
      mean_nxt_dbg <= mean_nxt_o;
    end
  end

endmodule
