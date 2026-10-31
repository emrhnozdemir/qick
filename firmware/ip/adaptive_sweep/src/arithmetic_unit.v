`timescale 1ns / 1ps

module arithmetic_unit(
  input clk,
  input rst_n,

  input [3:0] state_i,
  input [3:0] phase_i,
  input start_i,
  input [15:0] threshold_i,
  input lower_i,

  input [67:0] pa_i,
  input [67:0] pb_i,
  input psub_i,
  input [33:0] fa_i,
  input [33:0] fb_i,
  input fsub_i,

  input [63:0] pmax_i,
  input [3:0] noise_shift_i,
  input [31:0] half_i,
  input [3:0] k_i,

  output [67:0] palu_o,
  output pless_o,
  output [31:0] falu_o,
  output fless_o,
  output [63:0] sh_out_o,
  output [6:0] enc_pos_o,
  output enc_zero_o,
  output [67:0] acc_o,
  output [66:0] t_o
);

  localparam S_IDLE = 4'd0, S_GRID_END = 4'd7, S_NOISE = 4'd9, S_BAR = 4'd10, S_PLAN = 4'd13;

  reg [67:0] acc;
  reg [66:0] t;

  wire [68:0] palu = {1'b0, pa_i} + {1'b0, psub_i ? ~pb_i : pb_i} + {68'd0, psub_i};
  wire [34:0] falu = {1'b0, fa_i} + {1'b0, fsub_i ? ~fb_i : fb_i} + {34'd0, fsub_i};

  wire [63:0] sh_in = (state_i == S_PLAN) ? {32'd0, half_i} : pmax_i;
  wire [3:0] sh_amt = (state_i == S_PLAN) ? k_i : noise_shift_i;
  wire [63:0] sh_out = sh_in >> sh_amt;

  priority_encoder encoder(
    .value_i(acc[64:0]),
    .position_o(enc_pos_o),
    .zero_o(enc_zero_o)
  );

  always @(posedge clk) begin
    if (!rst_n) begin
      acc <= 0;
      t <= 0;
    end else begin
      case (state_i)
        S_IDLE:
          if (start_i)
            acc <= {52'd0, threshold_i};

        S_GRID_END: begin
          acc <= palu[67:0];
          t <= {sh_out, 3'b000};
        end

        S_NOISE:
          t <= {3'b000, sh_out};

        S_BAR:
          acc <= palu[67:0];

        S_PLAN:
          case (phase_i)
            4'd2: acc <= palu[67:0];
            4'd3: acc <= palu[67:0];
            4'd4: if (lower_i) acc <= palu[67:0];
          endcase
      endcase
    end
  end

  assign palu_o = palu[67:0];
  assign pless_o = ~palu[68];
  assign falu_o = falu[31:0];
  assign fless_o = ~falu[34];
  assign sh_out_o = sh_out;
  assign acc_o = acc;
  assign t_o = t;

endmodule
