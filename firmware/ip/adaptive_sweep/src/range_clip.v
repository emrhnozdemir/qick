`timescale 1ns / 1ps

module range_clip #(
  parameter W = 34
) (
  input wire [W-1:0] a_i,
  input wire [W-1:0] lo_i,
  input wire [W-1:0] hi_i,
  input wire is_signed_i,

  output wire [W-1:0] y_o
);

  wire a_gt_lo;
  wire a_ge_lo;
  wire a_eq_lo;
  wire a_gt_hi;
  wire a_ge_hi;
  wire a_eq_hi;

  value_comparator #(.W(W)) u_cmp_lo (
    .a_i         (a_i),
    .b_i         (lo_i),
    .is_signed_i (is_signed_i),
    .gt_o        (a_gt_lo),
    .ge_o        (a_ge_lo),
    .eq_o        (a_eq_lo)
  );

  value_comparator #(.W(W)) u_cmp_hi (
    .a_i         (a_i),
    .b_i         (hi_i),
    .is_signed_i (is_signed_i),
    .gt_o        (a_gt_hi),
    .ge_o        (a_ge_hi),
    .eq_o        (a_eq_hi)
  );

  assign y_o = (!a_ge_lo) ? lo_i : (a_gt_hi ? hi_i : a_i);

endmodule
