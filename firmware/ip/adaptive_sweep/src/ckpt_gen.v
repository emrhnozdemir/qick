`timescale 1ns / 1ps

module ckpt_gen (
  input wire clk,
  input wire rst_n,

  input wire arm_i,
  input wire [1:0] dens_i,
  input wire hit_i,

  output reg [31:0] ckpt_o,
  output reg [4:0] j_o,
  output reg [1:0] midx_o
);

  reg [4:0] bk;
  reg [1:0] pos;
  reg [31:0] step;
  reg [1:0] dens_r;

  wire [2:0] pos_x = {1'b0, pos} + ((dens_r == 2'd2) ? 3'd1 : (dens_r == 2'd1) ? 3'd2 : 3'd4);
  wire wrap = pos_x[2];
  wire [1:0] pos_n = pos_x[1:0];
  wire [4:0] bk_n = wrap ? (bk + 5'd1) : bk;
  wire [31:0] inc = (dens_r == 2'd2) ? step : (dens_r == 2'd1) ? (step << 1) : (step << 2);

  reg [4:0] j_w;
  reg [1:0] midx_w;

  always @(*) begin
    case (pos_n)
      2'd0: begin
        midx_w = 2'd0;
        j_w = bk_n;
      end

      2'd1: begin
        midx_w = 2'd2;
        j_w = bk_n - 5'd2;
      end

      2'd2: begin
        midx_w = 2'd1;
        j_w = bk_n - 5'd1;
      end

      default: begin
        midx_w = 2'd3;
        j_w = bk_n - 5'd2;
      end
    endcase
  end

  always @(posedge clk) begin
    if (!rst_n) begin
      ckpt_o <= 32'd4;
      j_o <= 5'd2;
      midx_o <= 2'd0;
      bk <= 5'd2;
      pos <= 2'd0;
      step <= 32'd1;
      dens_r <= 2'd0;
    end else if (arm_i) begin
      ckpt_o <= (dens_i == 2'd2) ? 32'd8 : 32'd4;
      j_o <= (dens_i == 2'd2) ? 5'd3 : 5'd2;
      midx_o <= 2'd0;
      bk <= (dens_i == 2'd2) ? 5'd3 : 5'd2;
      pos <= 2'd0;
      step <= (dens_i == 2'd2) ? 32'd2 : 32'd1;
      dens_r <= dens_i;
    end else if (hit_i) begin
      ckpt_o <= ckpt_o + inc;
      j_o <= j_w;
      midx_o <= midx_w;
      bk <= bk_n;
      pos <= pos_n;
      step <= wrap ? (step << 1) : step;
      dens_r <= dens_r;
    end else begin
      ckpt_o <= ckpt_o;
      j_o <= j_o;
      midx_o <= midx_o;
      bk <= bk;
      pos <= pos;
      step <= step;
      dens_r <= dens_r;
    end
  end

endmodule
