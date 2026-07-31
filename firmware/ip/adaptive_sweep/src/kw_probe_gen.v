`timescale 1ns / 1ps

module kw_probe_gen (
  input wire [31:0] x_i,
  input wire [31:0] c_i,
  input wire [31:0] f_lo_i,
  input wire [31:0] f_hi_i,

  output wire [31:0] x_plus_o,
  output wire [31:0] x_minus_o
);

  wire signed [33:0] xs = {2'b00, x_i};
  wire signed [33:0] cs = {2'b00, c_i};
  wire signed [33:0] lo = {2'b00, f_lo_i};
  wire signed [33:0] hi = {2'b00, f_hi_i};

  wire [33:0] plus_clip;
  wire [33:0] minus_clip;

  range_clip #(.W(34)) u_clip_plus (
    .a_i         (xs + cs),
    .lo_i        (lo),
    .hi_i        (hi),
    .is_signed_i (1'b1),
    .y_o         (plus_clip)
  );

  range_clip #(.W(34)) u_clip_minus (
    .a_i         (xs - cs),
    .lo_i        (lo),
    .hi_i        (hi),
    .is_signed_i (1'b1),
    .y_o         (minus_clip)
  );

  assign x_plus_o = plus_clip[31:0];
  assign x_minus_o = minus_clip[31:0];

endmodule
