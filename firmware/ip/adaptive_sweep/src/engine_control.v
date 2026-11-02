`timescale 1ns / 1ps

module engine_control(
  input clk,
  input rst_n,

  input start_i,
  input abort_i,
  input freq_ack_i,
  input amp_valid_i,

  input seen_i,
  input grid_last_i,
  input stop_i,
  input cap_i,
  input pless_i,
  input fless_i,

  input [63:0] p_i,
  input [63:0] g_i,
  input [63:0] pmax_i,
  input [63:0] worst_i,
  input [63:0] gl_i,
  input [63:0] gb_i,
  input [63:0] gh_i,
  input [63:0] dl_i,
  input [63:0] dr_i,
  input [67:0] acc_i,
  input [66:0] t_i,

  input [31:0] target_i,
  input [31:0] step_i,
  input [31:0] lo_i,
  input [31:0] b_i,
  input [31:0] hi_i,
  input [31:0] sl_i,
  input [31:0] sr_i,
  input [31:0] short_side_i,
  input [31:0] long_side_i,
  input [31:0] span_i,
  input [31:0] min_step_i,
  input [6:0] lead_s_i,
  input [6:0] lead_d_i,
  input go_up_i,

  output [4:0] state_o,
  output reg [67:0] pa_o,
  output reg [67:0] pb_o,
  output reg psub_o,
  output reg [33:0] fa_o,
  output reg [33:0] fb_o,
  output reg fsub_o,

  output freq_valid_o,
  output reg probe_arm_o,
  output measuring_o,
  output busy_o,
  output reg done_o,
  output converged_o,
  output capped_o,
  output nothing_o,
  output window_o,
  output [2:0] decision_o
);

  localparam S_IDLE = 5'd0, S_PRESENT = 5'd1, S_MEASURE = 5'd2, S_PMAX = 5'd3,
             S_GRID1 = 5'd4, S_GRID2 = 5'd5, S_GRID_END = 5'd6, S_SEEN = 5'd7,
             S_NOISE = 5'd8, S_BAR = 5'd9, S_BETTER = 5'd10, S_WIDTH = 5'd11,
             S_PLAN0 = 5'd12, S_PLAN1 = 5'd13, S_PLAN2 = 5'd14, S_PLAN3 = 5'd15,
             S_PLAN4 = 5'd16, S_PLAN5 = 5'd17, S_PLAN6 = 5'd18, S_PLAN7 = 5'd19,
             S_PLAN8 = 5'd20, S_PLAN9 = 5'd21, S_GO = 5'd22, S_DONE = 5'd23;

  localparam E_NONE = 3'd0, E_GRID = 3'd1, E_BETTER = 3'd2, E_BORDER = 3'd3,
             E_CONVERGED = 3'd4, E_CAPPED = 3'd5, E_NOTHING = 3'd6, E_WINDOW = 3'd7;

  reg [4:0] state, next_state;
  reg [2:0] decision;

  always @(posedge clk) begin
    if (!rst_n)
      state <= S_IDLE;
    else
      state <= next_state;
  end

  always @(*) begin
    if (start_i)
      next_state = S_PRESENT;
    else if (abort_i)
      next_state = S_IDLE;
    else
      case (state)
        S_PRESENT: next_state = freq_ack_i ? S_MEASURE : S_PRESENT;
        S_MEASURE: next_state = amp_valid_i ? S_PMAX : S_MEASURE;
        S_PMAX: next_state = seen_i ? S_NOISE : S_GRID1;
        S_GRID1: next_state = S_GRID2;
        S_GRID2: next_state = grid_last_i ? S_GRID_END : S_PRESENT;
        S_GRID_END: next_state = S_SEEN;
        S_SEEN: next_state = S_WIDTH;
        S_NOISE: next_state = S_BAR;
        S_BAR: next_state = S_BETTER;
        S_BETTER: next_state = S_WIDTH;
        S_WIDTH: next_state = nothing_o ? S_DONE : S_PLAN0;
        S_PLAN0: next_state = fless_i ? S_DONE : S_PLAN1;
        S_PLAN1: next_state = fless_i ? S_DONE : S_PLAN2;
        S_PLAN2: next_state = S_PLAN3;
        S_PLAN3: next_state = S_PLAN4;
        S_PLAN4: next_state = S_PLAN5;
        S_PLAN5: next_state = S_PLAN6;
        S_PLAN6: next_state = cap_i ? S_DONE : S_PLAN7;
        S_PLAN7: next_state = stop_i ? S_GO : S_PLAN8;
        S_PLAN8: next_state = S_PLAN9;
        S_PLAN9: next_state = S_GO;
        S_GO: next_state = stop_i ? S_DONE : S_PRESENT;
        default: next_state = S_IDLE;
      endcase
  end

  always @(*) begin
    case (state)
      S_PMAX: begin
        pa_o = {4'd0, pmax_i};
        pb_o = {4'd0, p_i};
        psub_o = 1'b1;
      end
      S_GRID1: begin
        pa_o = {4'd0, gb_i};
        pb_o = {4'd0, g_i};
        psub_o = 1'b1;
      end
      S_GRID2: begin
        pa_o = {4'd0, worst_i};
        pb_o = {4'd0, g_i};
        psub_o = 1'b1;
      end
      S_GRID_END: begin
        pa_o = {4'd0, gb_i};
        pb_o = {4'd0, worst_i};
        psub_o = 1'b1;
      end
      S_SEEN: begin
        pa_o = {1'b0, t_i};
        pb_o = acc_i;
        psub_o = 1'b1;
      end
      S_BAR: begin
        pa_o = {4'd0, gb_i};
        pb_o = {1'b0, t_i};
        psub_o = 1'b0;
      end
      S_BETTER: begin
        pa_o = acc_i;
        pb_o = {4'd0, g_i};
        psub_o = 1'b1;
      end
      S_PLAN0: begin
        pa_o = {4'd0, gb_i};
        pb_o = {4'd0, gl_i};
        psub_o = 1'b1;
      end
      S_PLAN1: begin
        pa_o = {4'd0, gb_i};
        pb_o = {4'd0, gh_i};
        psub_o = 1'b1;
      end
      S_PLAN2: begin
        pa_o = {4'd0, dl_i};
        pb_o = {4'd0, dr_i};
        psub_o = 1'b0;
      end
      S_PLAN3: begin
        pa_o = {4'd0, dl_i};
        pb_o = {4'd0, dr_i};
        psub_o = 1'b1;
      end
      S_PLAN4: begin
        pa_o = 68'd0;
        pb_o = acc_i;
        psub_o = 1'b1;
      end
      default: begin
        pa_o = 68'd0;
        pb_o = 68'd0;
        psub_o = 1'b0;
      end
    endcase
  end

  always @(*) begin
    case (state)
      S_GRID2: begin
        fa_o = {2'd0, target_i};
        fb_o = {2'd0, step_i};
        fsub_o = 1'b0;
      end
      S_WIDTH: begin
        fa_o = {2'd0, hi_i};
        fb_o = {2'd0, lo_i};
        fsub_o = 1'b1;
      end
      S_PLAN0: begin
        fa_o = {2'd0, b_i};
        fb_o = {2'd0, lo_i};
        fsub_o = 1'b1;
      end
      S_PLAN1: begin
        fa_o = {2'd0, hi_i};
        fb_o = {2'd0, b_i};
        fsub_o = 1'b1;
      end
      S_PLAN2: begin
        fa_o = {2'd0, sr_i};
        fb_o = {2'd0, sl_i};
        fsub_o = 1'b1;
      end
      S_PLAN3: begin
        fa_o = {short_side_i, 2'b00};
        fb_o = {2'd0, long_side_i};
        fsub_o = 1'b1;
      end
      S_PLAN4: begin
        fa_o = {2'd0, min_step_i};
        fb_o = {2'd0, sl_i};
        fsub_o = 1'b1;
      end
      S_PLAN5: begin
        fa_o = {2'd0, min_step_i};
        fb_o = {2'd0, sr_i};
        fsub_o = 1'b1;
      end
      S_PLAN6: begin
        fa_o = {27'd0, lead_s_i};
        fb_o = {27'd0, lead_d_i};
        fsub_o = 1'b1;
      end
      S_PLAN7: begin
        fa_o = {2'd0, span_i >> 2};
        fb_o = {2'd0, span_i >> 3};
        fsub_o = 1'b0;
      end
      S_PLAN8: begin
        fa_o = {2'd0, span_i};
        fb_o = {1'b0, min_step_i, 1'b0};
        fsub_o = 1'b1;
      end
      S_PLAN9: begin
        fa_o = {2'd0, min_step_i};
        fb_o = {2'd0, step_i};
        fsub_o = 1'b1;
      end
      S_GO: begin
        fa_o = {2'd0, b_i};
        fb_o = {2'd0, step_i};
        fsub_o = ~go_up_i;
      end
      default: begin
        fa_o = 34'd0;
        fb_o = 34'd0;
        fsub_o = 1'b0;
      end
    endcase
  end

  always @(posedge clk) begin
    if (!rst_n) begin
      decision <= E_NONE;
      probe_arm_o <= 0;
      done_o <= 0;
    end else begin
      probe_arm_o <= 0;
      done_o <= 0;
      if (start_i)
        decision <= E_NONE;
      else if (!abort_i)
        case (state)
          S_PRESENT:
            probe_arm_o <= freq_ack_i;

          S_GRID1:
            decision <= E_GRID;

          S_SEEN:
            if (!pless_i)
              decision <= E_NOTHING;

          S_BETTER:
            decision <= pless_i ? E_BETTER : E_BORDER;

          S_PLAN0, S_PLAN1:
            if (fless_i)
              decision <= E_WINDOW;

          S_PLAN6:
            if (cap_i)
              decision <= E_CAPPED;

          S_GO:
            if (stop_i)
              decision <= E_CONVERGED;

          S_DONE:
            done_o <= 1;
        endcase
    end
  end

  assign state_o = state;
  assign freq_valid_o = (state == S_PRESENT);
  assign measuring_o = (state == S_MEASURE);
  assign busy_o = (state != S_IDLE);
  assign converged_o = (decision == E_CONVERGED);
  assign capped_o = (decision == E_CAPPED);
  assign nothing_o = (decision == E_NOTHING);
  assign window_o = (decision == E_WINDOW);
  assign decision_o = decision;

endmodule
