`timescale 1ns / 1ps

module step_planner(
  input clk,
  input rst_n,

  input [3:0] state_i,
  input [3:0] phase_i,
  input start_i,
  input [31:0] step_i,
  input [31:0] min_step_i,
  input [15:0] max_iteration_i,

  input [67:0] palu_i,
  input pless_i,
  input [31:0] falu_i,
  input fless_i,
  input [31:0] sh_out_i,
  input [6:0] enc_pos_i,
  input enc_zero_i,

  output [31:0] step_o,
  output [31:0] min_step_o,
  output [31:0] sl_o,
  output [31:0] sr_o,
  output [63:0] dl_o,
  output [63:0] dr_o,
  output [31:0] short_side_o,
  output [31:0] long_side_o,
  output [31:0] span_o,
  output [31:0] half_o,
  output [6:0] lead_s_o,
  output [6:0] lead_d_o,
  output [3:0] k_o,
  output lower_o,
  output stop_o,
  output balanced_o,
  output side_o,
  output cap_o,
  output go_up_o,
  output [15:0] iteration_o,
  output [31:0] width_o
);

  localparam S_IDLE = 4'd0, S_SEEN = 4'd8, S_WIDTH = 4'd12, S_PLAN = 4'd13;

  reg [31:0] step;
  reg [31:0] min_step;
  reg [15:0] max_iteration;

  reg [31:0] sl, sr;
  reg [63:0] dl, dr;
  reg left_long;
  reg ratio_ok;
  reg lower;
  reg sl_big;
  reg sr_big;
  reg right;
  reg zero_s;
  reg jzero;
  reg [6:0] lead_s;
  reg [6:0] lead_d;
  reg stop;
  reg balanced;
  reg side;
  reg wide;
  reg [3:0] k;
  reg [15:0] iteration;
  reg [31:0] width;

  wire [31:0] span = side ? sr : sl;
  wire [31:0] half = right ? (sr >> 1) : (sl >> 1);

  wire stop_c = ~sl_big & ~sr_big;
  wire balanced_c = sl_big & sr_big & ratio_ok;
  wire side_c = balanced_c ? right : ~left_long;
  wire [3:0] k_clamped = fless_i ? 4'd0 : ((falu_i[6:4] != 3'd0) ? 4'd15 : falu_i[3:0]);
  wire [3:0] k_c = jzero ? 4'd15 : k_clamped;
  wire cap = ~stop_c & (iteration == max_iteration);

  always @(posedge clk) begin
    if (!rst_n) begin
      step <= 0;
      min_step <= 0;
      max_iteration <= 0;
      sl <= 0;
      sr <= 0;
      dl <= 0;
      dr <= 0;
      left_long <= 0;
      ratio_ok <= 0;
      lower <= 0;
      sl_big <= 0;
      sr_big <= 0;
      right <= 0;
      zero_s <= 0;
      jzero <= 0;
      lead_s <= 0;
      lead_d <= 0;
      stop <= 0;
      balanced <= 0;
      side <= 0;
      wide <= 0;
      k <= 0;
      iteration <= 0;
      width <= 0;
    end else begin
      case (state_i)
        S_IDLE:
          if (start_i) begin
            step <= step_i;
            min_step <= (min_step_i == 32'd0) ? 32'd1 : min_step_i;
            max_iteration <= (max_iteration_i == 16'd0) ? 16'd1 : max_iteration_i;
            iteration <= 0;
            k <= 0;
          end

        S_SEEN:
          step <= 0;

        S_WIDTH:
          width <= falu_i;

        S_PLAN:
          case (phase_i)
            4'd0: begin
              dl <= pless_i ? 64'd0 : palu_i[63:0];
              sl <= falu_i;
            end
            4'd1: begin
              dr <= pless_i ? 64'd0 : palu_i[63:0];
              sr <= falu_i;
            end
            4'd2:
              left_long <= fless_i;
            4'd3: begin
              lead_s <= enc_pos_i;
              zero_s <= enc_zero_i;
              lower <= pless_i;
              ratio_ok <= ~fless_i;
            end
            4'd4:
              sl_big <= fless_i;
            4'd5: begin
              lead_d <= enc_pos_i;
              jzero <= zero_s | enc_zero_i;
              right <= ~lower & ~enc_zero_i;
              sr_big <= fless_i;
            end
            4'd6: begin
              stop <= stop_c;
              balanced <= balanced_c;
              side <= side_c;
              if (!cap)
                k <= (balanced_c | stop_c) ? k_c : 4'd0;
            end
            4'd7:
              step <= (balanced | stop) ? (jzero ? 32'd0 : sh_out_i) : falu_i;
            4'd8:
              wide <= ~fless_i;
            4'd9: begin
              step <= wide ? (fless_i ? step : min_step) : (span >> 1);
              iteration <= iteration + 16'd1;
            end
          endcase
      endcase
    end
  end

  assign step_o = step;
  assign min_step_o = min_step;
  assign sl_o = sl;
  assign sr_o = sr;
  assign dl_o = dl;
  assign dr_o = dr;
  assign short_side_o = left_long ? sr : sl;
  assign long_side_o = left_long ? sl : sr;
  assign span_o = span;
  assign half_o = half;
  assign lead_s_o = lead_s;
  assign lead_d_o = lead_d;
  assign k_o = k;
  assign lower_o = lower;
  assign stop_o = stop;
  assign balanced_o = balanced;
  assign side_o = side;
  assign cap_o = cap;
  assign go_up_o = stop ? right : side;
  assign iteration_o = iteration;
  assign width_o = width;

endmodule
