`timescale 1ns / 1ps

module squarer(
  input clk,
  input rst_n,

  input signed [31:0] value_i,

  output [63:0] square_o
);

  reg signed [17:0] low;
  reg signed [17:0] high;

  always @(posedge clk) begin
    if (!rst_n) begin
      low <= 0;
      high <= 0;
    end else begin
      low <= {2'b00, value_i[15:0]};
      high <= {{2{value_i[31]}}, value_i[31:16]};
    end
  end

  reg signed [35:0] low_square;
  reg signed [35:0] cross;
  reg signed [35:0] high_square;

  always @(posedge clk) begin
    if (!rst_n) begin
      low_square <= 0;
      cross <= 0;
      high_square <= 0;
    end else begin
      low_square <= low * low;
      cross <= high * low;
      high_square <= high * high;
    end
  end

  reg signed [36:0] low_term;
  reg signed [36:0] cross_term;
  reg signed [36:0] high_term;

  always @(posedge clk) begin
    if (!rst_n) begin
      low_term <= 0;
      cross_term <= 0;
      high_term <= 0;
    end else begin
      low_term <= low_square;
      cross_term <= cross <<< 1;
      high_term <= high_square;
    end
  end

  reg [63:0] total;

  always @(posedge clk) begin
    if (!rst_n)
      total <= 0;
    else
      total <= {{27{low_term[36]}}, low_term}
             + ({{27{cross_term[36]}}, cross_term} <<< 16)
             + ({{27{high_term[36]}}, high_term} <<< 32);
  end

  assign square_o = total;

endmodule
