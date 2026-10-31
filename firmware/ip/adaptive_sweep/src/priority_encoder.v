`timescale 1ns / 1ps

module priority_encoder(
  input [64:0] value_i,

  output [6:0] position_o,
  output zero_o
);

  wire [8:0] group = {value_i[64], |value_i[63:56], |value_i[55:48], |value_i[47:40], |value_i[39:32],
                      |value_i[31:24], |value_i[23:16], |value_i[15:8], |value_i[7:0]};

  wire [3:0] group_index = group[8] ? 4'd8 :
                           group[7] ? 4'd7 :
                           group[6] ? 4'd6 :
                           group[5] ? 4'd5 :
                           group[4] ? 4'd4 :
                           group[3] ? 4'd3 :
                           group[2] ? 4'd2 :
                           group[1] ? 4'd1 : 4'd0;

  reg [7:0] octet;

  always @(*) begin
    case (group_index)
      4'd8: octet = {7'd0, value_i[64]};
      4'd7: octet = value_i[63:56];
      4'd6: octet = value_i[55:48];
      4'd5: octet = value_i[47:40];
      4'd4: octet = value_i[39:32];
      4'd3: octet = value_i[31:24];
      4'd2: octet = value_i[23:16];
      4'd1: octet = value_i[15:8];
      default: octet = value_i[7:0];
    endcase
  end

  wire [2:0] bit_index = octet[7] ? 3'd7 :
                         octet[6] ? 3'd6 :
                         octet[5] ? 3'd5 :
                         octet[4] ? 3'd4 :
                         octet[3] ? 3'd3 :
                         octet[2] ? 3'd2 :
                         octet[1] ? 3'd1 : 3'd0;

  assign position_o = {group_index, bit_index};
  assign zero_o = (group == 9'd0);

endmodule
