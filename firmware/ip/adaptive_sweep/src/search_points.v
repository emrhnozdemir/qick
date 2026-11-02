`timescale 1ns / 1ps

module search_points(
  input clk,
  input rst_n,

  input [4:0] state_i,
  input start_i,
  input dip_i,
  input [31:0] start_freq_i,
  input [15:0] n_points_i,
  input [31:0] x0_i,
  input [31:0] f_lo_i,
  input [31:0] f_hi_i,

  input amp_valid_i,
  input [63:0] amp_data_i,

  input pless_i,
  input [31:0] falu_i,
  input [3:0] enc_pos_i,
  input side_i,
  input stop_i,

  output [63:0] p_o,
  output [63:0] g_o,
  output [63:0] pmax_o,
  output [63:0] worst_o,
  output [31:0] lo_o,
  output [31:0] b_o,
  output [31:0] hi_o,
  output [63:0] gl_o,
  output [63:0] gb_o,
  output [63:0] gh_o,
  output [31:0] target_o,
  output [15:0] idx_o,
  output grid_last_o,
  output [3:0] noise_shift_o,
  output seen_o,
  output dip_o
);

  localparam S_MEASURE = 5'd2, S_PMAX = 5'd3, S_GRID1 = 5'd4, S_GRID2 = 5'd5,
             S_GRID_END = 5'd6, S_SEEN = 5'd7, S_BETTER = 5'd10, S_GO = 5'd22;

  reg dip;
  reg grid_mode;
  reg [15:0] last_idx;
  reg [31:0] x0;
  reg [31:0] f_hi;
  reg [3:0] noise_shift;

  reg [31:0] target;
  reg [15:0] idx;
  reg [63:0] p;
  reg [63:0] pmax;
  reg [63:0] worst;

  reg [31:0] lo, b, hi;
  reg [63:0] gl, gb, gh;
  reg [31:0] prev_f;
  reg [63:0] prev_g;
  reg need_right;
  reg seen;

  wire [63:0] g = dip ? ~p : p;
  wire first = (idx == 16'd0);

  always @(posedge clk) begin
    if (!rst_n) begin
      dip <= 0;
      grid_mode <= 0;
      last_idx <= 0;
      x0 <= 0;
      f_hi <= 0;
      noise_shift <= 0;
      target <= 0;
      idx <= 0;
      p <= 0;
      pmax <= 0;
      worst <= 0;
      lo <= 0;
      b <= 0;
      hi <= 0;
      gl <= 0;
      gb <= 0;
      gh <= 0;
      prev_f <= 0;
      prev_g <= 0;
      need_right <= 0;
      seen <= 0;
    end else begin
      if (start_i) begin
        dip <= dip_i;
        grid_mode <= (n_points_i >= 16'd2);
        last_idx <= (n_points_i >= 16'd2) ? (n_points_i - 16'd1) : 16'd2;
        x0 <= x0_i;
        f_hi <= f_hi_i;
        target <= (n_points_i >= 16'd2) ? start_freq_i : f_lo_i;
        idx <= 0;
        pmax <= 0;
        worst <= 64'hFFFFFFFFFFFFFFFF;
        need_right <= 0;
        seen <= 0;
      end else begin
        case (state_i)
          S_MEASURE:
            if (amp_valid_i)
              p <= amp_data_i;

          S_PMAX:
            if (pless_i)
              pmax <= p;

          S_GRID1: begin
            noise_shift <= enc_pos_i;
            if (first | pless_i) begin
              lo <= first ? target : prev_f;
              gl <= first ? g : prev_g;
              b <= target;
              gb <= g;
              need_right <= 1;
            end else if (need_right) begin
              hi <= target;
              gh <= g;
              need_right <= 0;
            end
            prev_f <= target;
            prev_g <= g;
          end

          S_GRID2: begin
            if (~pless_i)
              worst <= g;
            idx <= idx + 16'd1;
            if (idx != last_idx)
              target <= grid_mode ? falu_i : (first ? x0 : f_hi);
          end

          S_GRID_END:
            if (need_right) begin
              hi <= b;
              gh <= gb;
            end

          S_SEEN:
            if (pless_i)
              seen <= 1;

          S_BETTER:
            if (pless_i) begin
              if (side_i) begin
                lo <= b;
                gl <= gb;
              end else begin
                hi <= b;
                gh <= gb;
              end
              b <= target;
              gb <= g;
            end else begin
              if (side_i) begin
                hi <= target;
                gh <= g;
              end else begin
                lo <= target;
                gl <= g;
              end
            end

          S_GO:
            if (stop_i)
              b <= falu_i;
            else
              target <= falu_i;
        endcase
      end
    end
  end

  assign p_o = p;
  assign g_o = g;
  assign pmax_o = pmax;
  assign worst_o = worst;
  assign lo_o = lo;
  assign b_o = b;
  assign hi_o = hi;
  assign gl_o = gl;
  assign gb_o = gb;
  assign gh_o = gh;
  assign target_o = target;
  assign idx_o = idx;
  assign grid_last_o = (idx == last_idx);
  assign noise_shift_o = noise_shift;
  assign seen_o = seen;
  assign dip_o = dip;

endmodule
