`timescale 1ns / 1ps

module tone_registers(
  input clk,
  input rst_n,

  input select_i,
  input cfg_sweep_i,
  input cfg_search_i,
  input cfg_ratio_i,
  input [31:0] dt1_i,
  input [31:0] dt2_i,
  input [31:0] dt3_i,
  input [31:0] dt4_i,

  output reg [31:0] start_freq_o,
  output reg [31:0] f_lo_o,
  output reg [31:0] f_hi_o,
  output reg [31:0] x0_o,
  output reg [31:0] gen_base_o,
  output reg [36:0] ro_base_o,
  output reg [34:0] ratio_o
);

  always @(posedge clk) begin
    if (!rst_n)
      start_freq_o <= 0;
    else if (cfg_sweep_i & select_i)
      start_freq_o <= dt1_i;
  end

  always @(posedge clk) begin
    if (!rst_n) begin
      f_lo_o <= 0;
      f_hi_o <= 32'hFFFFFFFF;
      x0_o <= 0;
    end else if (cfg_search_i & select_i) begin
      f_lo_o <= dt1_i;
      f_hi_o <= dt2_i;
      x0_o <= dt3_i;
    end
  end

  always @(posedge clk) begin
    if (!rst_n) begin
      gen_base_o <= 0;
      ro_base_o <= 0;
      ratio_o <= 0;
    end else if (cfg_ratio_i & select_i) begin
      gen_base_o <= dt1_i;
      ro_base_o <= {dt4_i[4:0], dt2_i};
      ratio_o <= {dt4_i[7:5], dt3_i};
    end
  end

endmodule
