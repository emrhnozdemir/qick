`timescale 1ns / 1ps

module sched_lut #(
  parameter DEPTH = 64,
  parameter AW = 6,
  parameter W = 32
) (
  input wire clk,
  input wire wr_en,
  input wire [AW-1:0] wr_addr,
  input wire [W-1:0] wr_din,

  input wire [15:0] idx_i,
  input wire [AW:0] len_i,

  output wire [W-1:0] rd_data_o
);

  reg [W-1:0] mem [0:DEPTH-1];
  integer i;

  initial begin
    for (i = 0; i < DEPTH; i = i + 1)
      mem[i] = {W{1'b0}};
  end

  always @(posedge clk) begin
    if (wr_en)
      mem[wr_addr] <= wr_din;
  end

  wire [AW:0] len_eff = (len_i == {(AW+1){1'b0}}) ? {{AW{1'b0}}, 1'b1} : len_i;
  wire [AW:0] last = len_eff - {{AW{1'b0}}, 1'b1};
  wire [AW-1:0] addr = (idx_i >= {{(16-AW-1){1'b0}}, len_eff}) ? last[AW-1:0] : idx_i[AW-1:0];

  assign rd_data_o = mem[addr];

endmodule
