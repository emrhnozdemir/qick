`timescale 1ns / 1ps

module result_router (
  input wire [127:0] power_i,
  input wire valid_i,
  input wire dest_i,

  output wire [127:0] grid_data_o,
  output wire grid_valid_o,
  output wire [35:0] search_data_o,
  output wire search_valid_o
);

  wire wide = |power_i[127:36];

  assign grid_data_o = power_i;
  assign grid_valid_o = valid_i & ~dest_i;
  assign search_data_o = wide ? {36{1'b1}} : power_i[35:0];
  assign search_valid_o = valid_i & dest_i;

endmodule
