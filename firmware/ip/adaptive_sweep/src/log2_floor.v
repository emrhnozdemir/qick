`timescale 1ns / 1ps

module log2_floor (
  input wire [31:0] v_i,

  output reg [4:0] y_o
);

  integer k;

  always @(*) begin
    y_o = 5'd0;
    for (k = 1; k <= 31; k = k + 1) begin
      if (v_i[k])
        y_o = k[4:0];
      else
        y_o = y_o;
    end
  end

endmodule
