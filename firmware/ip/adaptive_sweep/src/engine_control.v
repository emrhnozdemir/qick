`timescale 1ns / 1ps

module engine_control(
  input clk,
  input rst_n,

  input start_i,
  input freq_ack_i,
  input amp_valid_i,

  input seen_i,
  input grid_last_i,
  input stop_i,
  input cap_i,
  input pless_i,

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

  output [3:0] state_o,
  output [3:0] phase_o,
  output reg [67:0] pa_o,
  output reg [67:0] pb_o,
  output reg psub_o,
  output reg [33:0] fa_o,
  output reg [33:0] fb_o,
  output reg fsub_o,

  output reg freq_valid_o,
  output reg probe_arm_o,
  output measuring_o,
  output reg busy_o,
  output reg done_o,
  output reg converged_o,
  output reg capped_o,
  output reg nothing_o,
  output [3:0] decision_o
);

  localparam S_IDLE = 4'd0, S_PRESENT = 4'd1, S_MEASURE = 4'd2, S_START = 4'd3,
             S_PMAX = 4'd4, S_GRID1 = 4'd5, S_GRID2 = 4'd6, S_GRID_END = 4'd7,
             S_SEEN = 4'd8, S_NOISE = 4'd9, S_BAR = 4'd10, S_BETTER = 4'd11,
             S_WIDTH = 4'd12, S_PLAN = 4'd13, S_GO = 4'd14, S_DONE = 4'd15;

  localparam E_NONE = 4'd0, E_GRID = 4'd1, E_BETTER = 4'd2, E_BORDER = 4'd3,
             E_CONVERGED = 4'd4, E_CAPPED = 4'd5, E_NOTHING = 4'd6;

  reg [3:0] state, next_state;
  reg [3:0] phase;
  reg [3:0] decision;

  always @(posedge clk) begin
    if (!rst_n)
      state <= S_IDLE;
    else
      state <= next_state;
  end

  always @(*) begin
    case (state)
      S_IDLE: next_state = start_i ? S_START : S_IDLE;
      S_START: next_state = S_PRESENT;
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
      S_WIDTH: next_state = nothing_o ? S_DONE : S_PLAN;
      S_PLAN: begin
        if (phase == 4'd6 && cap_i)
          next_state = S_DONE;
        else if (phase == 4'd7 && stop_i)
          next_state = S_GO;
        else if (phase == 4'd9)
          next_state = S_GO;
        else
          next_state = S_PLAN;
      end
      S_GO: next_state = stop_i ? S_DONE : S_PRESENT;
      S_DONE: next_state = S_IDLE;
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
      S_PLAN: begin
        case (phase)
          4'd0: begin
            pa_o = {4'd0, gb_i};
            pb_o = {4'd0, gl_i};
            psub_o = 1'b1;
          end
          4'd1: begin
            pa_o = {4'd0, gb_i};
            pb_o = {4'd0, gh_i};
            psub_o = 1'b1;
          end
          4'd2: begin
            pa_o = {4'd0, dl_i};
            pb_o = {4'd0, dr_i};
            psub_o = 1'b0;
          end
          4'd3: begin
            pa_o = {4'd0, dl_i};
            pb_o = {4'd0, dr_i};
            psub_o = 1'b1;
          end
          4'd4: begin
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
      S_PLAN: begin
        case (phase)
          4'd0: begin
            fa_o = {2'd0, b_i};
            fb_o = {2'd0, lo_i};
            fsub_o = 1'b1;
          end
          4'd1: begin
            fa_o = {2'd0, hi_i};
            fb_o = {2'd0, b_i};
            fsub_o = 1'b1;
          end
          4'd2: begin
            fa_o = {2'd0, sr_i};
            fb_o = {2'd0, sl_i};
            fsub_o = 1'b1;
          end
          4'd3: begin
            fa_o = {short_side_i, 2'b00};
            fb_o = {2'd0, long_side_i};
            fsub_o = 1'b1;
          end
          4'd4: begin
            fa_o = {2'd0, min_step_i};
            fb_o = {2'd0, sl_i};
            fsub_o = 1'b1;
          end
          4'd5: begin
            fa_o = {2'd0, min_step_i};
            fb_o = {2'd0, sr_i};
            fsub_o = 1'b1;
          end
          4'd6: begin
            fa_o = {27'd0, lead_s_i};
            fb_o = {27'd0, lead_d_i};
            fsub_o = 1'b1;
          end
          4'd7: begin
            fa_o = {2'd0, span_i >> 2};
            fb_o = {2'd0, span_i >> 3};
            fsub_o = 1'b0;
          end
          4'd8: begin
            fa_o = {2'd0, span_i};
            fb_o = {1'b0, min_step_i, 1'b0};
            fsub_o = 1'b1;
          end
          4'd9: begin
            fa_o = {2'd0, min_step_i};
            fb_o = {2'd0, step_i};
            fsub_o = 1'b1;
          end
          default: begin
            fa_o = 34'd0;
            fb_o = 34'd0;
            fsub_o = 1'b0;
          end
        endcase
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
      phase <= 0;
      decision <= E_NONE;
      freq_valid_o <= 0;
      probe_arm_o <= 0;
      busy_o <= 0;
      done_o <= 0;
      converged_o <= 0;
      capped_o <= 0;
      nothing_o <= 0;
    end else begin
      probe_arm_o <= 0;
      done_o <= 0;
      case (state)
        S_IDLE: begin
          freq_valid_o <= 0;
          if (start_i) begin
            decision <= E_NONE;
            busy_o <= 1;
            converged_o <= 0;
            capped_o <= 0;
            nothing_o <= 0;
          end
        end

        S_PRESENT: begin
          freq_valid_o <= ~freq_ack_i;
          probe_arm_o <= freq_ack_i;
        end

        S_GRID1:
          decision <= E_GRID;

        S_SEEN:
          if (!pless_i) begin
            nothing_o <= 1;
            decision <= E_NOTHING;
          end

        S_BETTER:
          decision <= pless_i ? E_BETTER : E_BORDER;

        S_WIDTH:
          phase <= 0;

        S_PLAN: begin
          phase <= phase + 4'd1;
          if (phase == 4'd6 && cap_i) begin
            capped_o <= 1;
            decision <= E_CAPPED;
          end
          if (phase > 4'd9)
            phase <= 0;
        end

        S_GO:
          if (stop_i) begin
            converged_o <= 1;
            decision <= E_CONVERGED;
          end

        S_DONE: begin
          busy_o <= 0;
          done_o <= 1;
        end
      endcase
    end
  end

  assign state_o = state;
  assign phase_o = phase;
  assign measuring_o = (state == S_MEASURE);
  assign decision_o = decision;

endmodule
