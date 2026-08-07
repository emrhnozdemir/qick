`timescale 1ns / 1ps

module stop_log (
  input wire clk,
  input wire rst_n,

  input wire clr_i,
  input wire wr_i,
  input wire [15:0] wr_entry_i,

  input wire rd_en_i,
  input wire [11:0] rd_addr_i,
  output wire [15:0] rd_data_o,
  output wire rd_valid_o,
  output reg [15:0] cnt_o
);

  reg [11:0] rd_addr_r;

  bram_stop_log u_mem (
    .clka  (clk),
    .wea   (wr_i),
    .addra (cnt_o[11:0]),
    .dina  (wr_entry_i),
    .clkb  (clk),
    .enb   (rd_en_i),
    .addrb (rd_addr_i),
    .doutb (rd_data_o)
  );

  always @(posedge clk) begin
    if (rd_en_i) begin
      rd_addr_r <= rd_addr_i;
    end else begin
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

  (* mark_debug = "true" *) reg wr_dbg;
  (* mark_debug = "true" *) reg [15:0] wr_entry_dbg;
  (* mark_debug = "true" *) reg [15:0] cnt_dbg;
  (* mark_debug = "true" *) reg rd_en_dbg;
  (* mark_debug = "true" *) reg [11:0] rd_addr_dbg;
  (* mark_debug = "true" *) reg [15:0] rd_data_dbg;
  (* mark_debug = "true" *) reg rd_valid_dbg;
  always @(posedge clk) begin
    if (!rst_n) begin
      wr_dbg <= 1'b0;
      wr_entry_dbg <= 16'd0;
      cnt_dbg <= 16'd0;
      rd_en_dbg <= 1'b0;
      rd_addr_dbg <= 12'd0;
      rd_data_dbg <= 16'd0;
      rd_valid_dbg <= 1'b0;
    end else begin
      wr_dbg <= wr_i;
      wr_entry_dbg <= wr_entry_i;
      cnt_dbg <= cnt_o;
      rd_en_dbg <= rd_en_i;
      rd_addr_dbg <= rd_addr_i;
      rd_data_dbg <= rd_data_o;
      rd_valid_dbg <= rd_valid_o;
    end
  end

endmodule
