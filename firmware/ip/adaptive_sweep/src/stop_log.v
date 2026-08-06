`timescale 1ns / 1ps

module stop_log (
  input wire clk,
  input wire rst_n,

  input wire clr_i,
  input wire wr_i,
  input wire [15:0] wr_entry_i,

  input wire rd_en_i,
  input wire [11:0] rd_addr_i,
  output reg [15:0] rd_data_o,
  output wire rd_valid_o,
  output reg [15:0] cnt_o
);

  reg [15:0] mem [0:4095];
  reg [11:0] rd_addr_r;

  integer mi;

  initial begin
    for (mi = 0; mi < 4096; mi = mi + 1)
      mem[mi] = 16'd0;
  end

  always @(posedge clk) begin
    if (wr_i)
      mem[cnt_o[11:0]] <= wr_entry_i;
  end

  always @(posedge clk) begin
    if (rd_en_i) begin
      rd_data_o <= mem[rd_addr_i];
      rd_addr_r <= rd_addr_i;
    end else begin
      rd_data_o <= rd_data_o;
      rd_addr_r <= rd_addr_r;
    end
  end

  assign rd_valid_o = ({4'd0, rd_addr_r} < cnt_o);

  always @(posedge clk) begin
    if (!rst_n)
      cnt_o <= 16'd0;
    else if (clr_i)
      cnt_o <= 16'd0;
    else if (wr_i)
      cnt_o <= cnt_o + 16'd1;
    else
      cnt_o <= cnt_o;
  end

endmodule
