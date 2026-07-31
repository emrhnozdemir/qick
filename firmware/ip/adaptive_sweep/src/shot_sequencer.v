`timescale 1ns / 1ps

module shot_sequencer (
  input wire clk,
  input wire rst_n,

  input wire arm_i,
  input wire shot_i,
  input wire [31:0] averager_value_i,
  input wire [31:0] n0_i,
  input wire stop_i,
  input wire stop_hold_i,

  (* mark_debug = "true" *) output reg armed_o,
  (* mark_debug = "true" *) output reg stopped_o,
  output wire first_o,
  output wire [31:0] n_o,
  output wire acc_clr_o,
  output wire acc_en_o,
  output wire is_last_o,
  output wire stop_now_o,
  output wire point_latch_o,
  output wire emit_o,
  output wire warmup_done_o,
  (* mark_debug = "true" *) output reg early_o,
  (* mark_debug = "true" *) output reg [31:0] n_used_o
);

  (* mark_debug = "true" *) reg [31:0] shot_cnt;
  (* mark_debug = "true" *) reg [31:0] avg_m1;
  (* mark_debug = "true" *) reg [31:0] n0_r;

  wire count_en = armed_o & shot_i;
  wire fold_en = count_en & ~stopped_o;

  assign first_o = (shot_cnt == 32'd0);
  assign n_o = shot_cnt + 32'd1;
  assign is_last_o = (shot_cnt == avg_m1);
  assign acc_clr_o = arm_i;
  assign acc_en_o = fold_en;
  assign stop_now_o = stop_i & fold_en & ~is_last_o;

  wire cap_now = count_en & is_last_o;

  assign point_latch_o = stop_now_o | (cap_now & ~stopped_o);
  assign emit_o = cap_now | (stop_now_o & ~stop_hold_i);
  assign warmup_done_o = armed_o & (shot_cnt >= n0_r);

  always @(posedge clk) begin
    if (!rst_n) begin
      armed_o <= 1'b0;
      stopped_o <= 1'b0;
      shot_cnt <= 32'd0;
      avg_m1 <= 32'd0;
      n0_r <= 32'd0;
      early_o <= 1'b0;
      n_used_o <= 32'd0;
    end else begin
      if (arm_i) begin
        armed_o <= 1'b1;
        stopped_o <= 1'b0;
        shot_cnt <= 32'd0;
        avg_m1 <= (averager_value_i == 32'd0) ? 32'd0 : averager_value_i - 32'd1;
        n0_r <= n0_i;
        early_o <= 1'b0;
        n_used_o <= n_used_o;
      end else if (count_en) begin
        avg_m1 <= avg_m1;
        n0_r <= n0_r;
        if (is_last_o) begin
          armed_o <= 1'b0;
          stopped_o <= 1'b0;
          shot_cnt <= 32'd0;
          if (stopped_o) begin
            early_o <= early_o;
            n_used_o <= n_used_o;
          end else begin
            early_o <= 1'b0;
            n_used_o <= n_o;
          end
        end else if (stop_now_o) begin
          early_o <= 1'b1;
          n_used_o <= n_o;
          if (stop_hold_i) begin
            armed_o <= 1'b1;
            stopped_o <= 1'b1;
            shot_cnt <= shot_cnt + 32'd1;
          end else begin
            armed_o <= 1'b0;
            stopped_o <= 1'b0;
            shot_cnt <= 32'd0;
          end
        end else begin
          armed_o <= 1'b1;
          stopped_o <= stopped_o;
          shot_cnt <= shot_cnt + 32'd1;
          early_o <= early_o;
          n_used_o <= n_used_o;
        end
      end else begin
        armed_o <= armed_o;
        stopped_o <= stopped_o;
        shot_cnt <= shot_cnt;
        avg_m1 <= avg_m1;
        n0_r <= n0_r;
        early_o <= early_o;
        n_used_o <= n_used_o;
      end
    end
  end

  (* mark_debug = "true" *) reg arm_dbg;
  (* mark_debug = "true" *) reg shot_dbg;
  (* mark_debug = "true" *) reg stop_dbg;
  (* mark_debug = "true" *) reg stop_hold_dbg;
  (* mark_debug = "true" *) reg count_en_dbg;
  (* mark_debug = "true" *) reg fold_en_dbg;
  (* mark_debug = "true" *) reg cap_now_dbg;
  (* mark_debug = "true" *) reg first_dbg;
  (* mark_debug = "true" *) reg acc_clr_dbg;
  (* mark_debug = "true" *) reg acc_en_dbg;
  (* mark_debug = "true" *) reg is_last_dbg;
  (* mark_debug = "true" *) reg stop_now_dbg;
  (* mark_debug = "true" *) reg point_latch_dbg;
  (* mark_debug = "true" *) reg emit_dbg;
  (* mark_debug = "true" *) reg warmup_done_dbg;
  always @(posedge clk) begin
    if (!rst_n) begin
      arm_dbg <= 1'b0;
      shot_dbg <= 1'b0;
      stop_dbg <= 1'b0;
      stop_hold_dbg <= 1'b0;
      count_en_dbg <= 1'b0;
      fold_en_dbg <= 1'b0;
      cap_now_dbg <= 1'b0;
      first_dbg <= 1'b0;
      acc_clr_dbg <= 1'b0;
      acc_en_dbg <= 1'b0;
      is_last_dbg <= 1'b0;
      stop_now_dbg <= 1'b0;
      point_latch_dbg <= 1'b0;
      emit_dbg <= 1'b0;
      warmup_done_dbg <= 1'b0;
    end else begin
      arm_dbg <= arm_i;
      shot_dbg <= shot_i;
      stop_dbg <= stop_i;
      stop_hold_dbg <= stop_hold_i;
      count_en_dbg <= count_en;
      fold_en_dbg <= fold_en;
      cap_now_dbg <= cap_now;
      first_dbg <= first_o;
      acc_clr_dbg <= acc_clr_o;
      acc_en_dbg <= acc_en_o;
      is_last_dbg <= is_last_o;
      stop_now_dbg <= stop_now_o;
      point_latch_dbg <= point_latch_o;
      emit_dbg <= emit_o;
      warmup_done_dbg <= warmup_done_o;
    end
  end

endmodule
