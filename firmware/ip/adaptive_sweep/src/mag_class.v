`timescale 1ns / 1ps

module mag_class (
  input wire [63:0] v_i,

  output reg [5:0] exp_o,
  output wire [3:0] mant_o
);

  integer k;

  always @(*) begin
    exp_o = 6'd0;
    for (k = 1; k <= 63; k = k + 1) begin
      if (v_i[k])
        exp_o = k[5:0];
      else
        exp_o = exp_o;
    end
  end

  wire [63:0] norm = v_i << (6'd63 - exp_o);

  assign mant_o = norm[62:59];

endmodule
