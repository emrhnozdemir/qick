`timescale 1ns / 1ps

module shot_counter(
  input clk,
  input rst_n,

  input arm_i,
  input shot_i,
  input [4:0] avg_shift_i,
  input [31:0] warmup_shots_i,
  input enable_i,
  input hold_i,

  input stop_i,
  input [4:0] stop_exponent_i,

  output acc_first_o,
  output acc_enable_o,
  output acc_subtract_o,

  output check_o,
  output [4:0] check_exponent_o,

  output retire_o,
  output stopping_o,
  output emit_o,
  output stop_pulse_o,
  output warmup_done_o,
  output [4:0] retire_shift_o,

  (* MARK_DEBUG = "TRUE" *) output reg stopped_early_o,
  (* MARK_DEBUG = "TRUE" *) output reg [31:0] shots_used_o
);

  (* MARK_DEBUG = "TRUE" *) reg [4:0] cap_exponent;
  reg [31:0] warmup_shots;

  always @(posedge clk) begin
    if (!rst_n) begin
      cap_exponent <= 0;
      warmup_shots <= 0;
    end else if (arm_i) begin
      cap_exponent <= (avg_shift_i > 5'd26) ? 5'd26 : avg_shift_i;
      warmup_shots <= warmup_shots_i;
    end
  end

  (* MARK_DEBUG = "TRUE" *) reg armed;
  (* MARK_DEBUG = "TRUE" *) reg stopped;
  (* MARK_DEBUG = "TRUE" *) reg [31:0] shot_count;
  (* MARK_DEBUG = "TRUE" *) reg [4:0] check_bit;
  reg previous_bit;

  wire counting = armed & shot_i;
  (* MARK_DEBUG = "TRUE" *) wire folding = counting & ~stopped;
  wire [31:0] shot_number = shot_count + 32'd1;
  wire at_cap = shot_number[cap_exponent];
  (* MARK_DEBUG = "TRUE" *) wire cap_reached = counting & at_cap;
  wire stop_active = stop_i & armed & ~stopped;

  wire watched_bit = shot_number[check_bit];

  assign check_o = folding & watched_bit & ~previous_bit & ~at_cap & enable_i;
  assign check_exponent_o = check_bit;

  assign acc_first_o = (shot_count == 0);
  assign acc_enable_o = folding;
  assign acc_subtract_o = ~shot_number[0];

  assign stopping_o = stop_active & ~cap_reached;
  assign retire_o = stopping_o | (cap_reached & ~stopped);
  assign emit_o = cap_reached | (stopping_o & ~hold_i);
  assign stop_pulse_o = stopping_o & ~hold_i;
  assign warmup_done_o = armed & (shot_count >= warmup_shots);
  assign retire_shift_o = stopping_o ? stop_exponent_i : cap_exponent;

  always @(posedge clk) begin
    if (!rst_n) begin
      check_bit <= 2;
      previous_bit <= 0;
    end else if (arm_i) begin
      check_bit <= 2;
      previous_bit <= 0;
    end else if (folding) begin
      if (watched_bit & ~previous_bit) begin
        check_bit <= check_bit + 5'd1;
        previous_bit <= 0;
      end else begin
        previous_bit <= watched_bit;
      end
    end
  end

  always @(posedge clk) begin
    if (!rst_n) begin
      armed <= 0;
      stopped <= 0;
      shot_count <= 0;
      stopped_early_o <= 0;
      shots_used_o <= 0;
    end else begin
      if (arm_i) begin
        armed <= 1;
        stopped <= 0;
        shot_count <= 0;
        stopped_early_o <= 0;
      end else if (counting) begin
        if (at_cap) begin
          armed <= 0;
          stopped <= 0;
          shot_count <= 0;
          if (!stopped) begin
            stopped_early_o <= 0;
            shots_used_o <= shot_number;
          end
        end else if (stop_active) begin
          stopped_early_o <= 1;
          shots_used_o <= 32'd1 << stop_exponent_i;
          if (hold_i) begin
            armed <= 1;
            stopped <= 1;
            shot_count <= shot_count + 32'd1;
          end else begin
            armed <= 0;
            stopped <= 0;
            shot_count <= 0;
          end
        end else begin
          armed <= 1;
          shot_count <= shot_count + 32'd1;
        end
      end else if (stop_active) begin
        stopped_early_o <= 1;
        shots_used_o <= 32'd1 << stop_exponent_i;
        if (hold_i) begin
          armed <= 1;
          stopped <= 1;
        end else begin
          armed <= 0;
          stopped <= 0;
          shot_count <= 0;
        end
      end
    end
  end

endmodule
