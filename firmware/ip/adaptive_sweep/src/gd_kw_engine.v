`timescale 1ns / 1ps

module gd_kw_engine (
  input wire clk,
  input wire rst_n,

  input wire start,
  input wire kw_mode_i,
  input wire use_lut_i,
  input wire dip_i,
  input wire [31:0] x0_i,
  input wire [31:0] f_lo_i,
  input wire [31:0] f_hi_i,
  input wire [31:0] fstep_i,
  input wire [31:0] min_step_i,
  input wire [15:0] max_iter_i,
  input wire [7:0] patience_i,
  input wire [4:0] lambda_i,
  input wire [15:0] m_min_i,
  input wire [15:0] m_max_i,

  input wire alut_wr_en,
  input wire [5:0] alut_wr_addr,
  input wire [31:0] alut_wr_data,
  input wire [6:0] alut_len_i,
  input wire clut_wr_en,
  input wire [5:0] clut_wr_addr,
  input wire [31:0] clut_wr_data,
  input wire [6:0] clut_len_i,

  (* mark_debug = "true" *) output reg [31:0] freq_word_o,
  (* mark_debug = "true" *) output reg freq_valid_o,
  input wire freq_ack_i,
  (* mark_debug = "true" *) output reg probe_arm_o,
  input wire amp_valid_i,
  input wire [63:0] amp_data_i,

  (* mark_debug = "true" *) output reg busy_o,
  (* mark_debug = "true" *) output reg done_o,
  (* mark_debug = "true" *) output reg converged_o,
  (* mark_debug = "true" *) output reg capped_o,
  output wire [31:0] x_o,
  output wire [15:0] iter_o,
  output wire [15:0] pairs_o,
  output wire [31:0] sd_hi_o
);

  localparam [3:0] S_IDLE = 4'd0, S_PAIR_INIT = 4'd1, S_PRESENT_A = 4'd2;
  localparam [3:0] S_MEAS_A = 4'd3, S_PRESENT_B = 4'd4, S_MEAS_B = 4'd5;
  localparam [3:0] S_DECIDE = 4'd6, S_STEP = 4'd7, S_TIE = 4'd8;
  localparam [3:0] S_CONV_CHK = 4'd9, S_DONE = 4'd10;
  localparam [3:0] S_DIFF = 4'd11, S_CERT = 4'd12;

  (* mark_debug = "true" *) reg [3:0] state;
  reg [3:0] next_state;

  (* mark_debug = "true" *) reg kw_mode_r, use_lut_r, dip_r;
  (* mark_debug = "true" *) reg [31:0] f_lo_r, f_hi_r, fstep_r, min_step_r;
  (* mark_debug = "true" *) reg [15:0] max_iter_r, m_min_r, m_max_r;
  (* mark_debug = "true" *) reg [7:0] patience_r;
  (* mark_debug = "true" *) reg [4:0] lambda_r;

  (* mark_debug = "true" *) reg [31:0] x;
  (* mark_debug = "true" *) reg [63:0] p_a_r, p_b_r;

  assign x_o = x;

  wire k_clr, k_en, m_clr, m_en;
  wire [15:0] k_q, m_q;

  match_counter #(.W(16)) u_k_cnt (
    .clk        (clk),
    .rst_n      (rst_n),
    .clr        (k_clr),
    .en         (k_en),
    .match_i    (16'd0),
    .q_o        (k_q),
    .at_match_o ()
  );

  match_counter #(.W(16)) u_m_cnt (
    .clk        (clk),
    .rst_n      (rst_n),
    .clr        (m_clr),
    .en         (m_en),
    .match_i    (16'd0),
    .q_o        (m_q),
    .at_match_o ()
  );

  assign iter_o = k_q;
  assign pairs_o = m_q;

  wire [31:0] a_lut_val, c_lut_val;

  sched_lut #(.DEPTH(64), .AW(6), .W(32)) u_a_lut (
    .clk       (clk),
    .wr_en     (alut_wr_en),
    .wr_addr   (alut_wr_addr),
    .wr_din    (alut_wr_data),
    .idx_i     (k_q),
    .len_i     (alut_len_i),
    .rd_data_o (a_lut_val)
  );

  sched_lut #(.DEPTH(64), .AW(6), .W(32)) u_c_lut (
    .clk       (clk),
    .wr_en     (clut_wr_en),
    .wr_addr   (clut_wr_addr),
    .wr_din    (clut_wr_data),
    .idx_i     (k_q),
    .len_i     (clut_len_i),
    .rd_data_o (c_lut_val)
  );

  wire [31:0] a_val = use_lut_r ? a_lut_val : fstep_r;
  wire [31:0] c_val = use_lut_r ? c_lut_val : fstep_r;

  wire [31:0] x_plus, x_minus;

  kw_probe_gen u_probe_gen (
    .x_i       (x),
    .c_i       (kw_mode_r ? c_val : fstep_r),
    .f_lo_i    (f_lo_r),
    .f_hi_i    (f_hi_r),
    .x_plus_o  (x_plus),
    .x_minus_o (x_minus)
  );

  wire [31:0] probe_a = kw_mode_r ? x_minus : x;
  wire [31:0] probe_b = x_plus;

  wire signed [64:0] dp;
  wire [64:0] dp_abs;
  wire dp_pos, dp_neg;

  probe_diff u_diff (
    .p_a_i    (p_a_r),
    .p_b_i    (p_b_r),
    .dip_i    (dip_r),
    .dp_o     (dp),
    .dp_abs_o (dp_abs),
    .pos_o    (dp_pos),
    .neg_o    (dp_neg)
  );

  (* mark_debug = "true" *) reg signed [64:0] dp_r;
  (* mark_debug = "true" *) reg [64:0] dp_abs_r;
  (* mark_debug = "true" *) reg dp_pos_r;
  (* mark_debug = "true" *) reg dp_neg_r;

  always @(posedge clk) begin
    if (!rst_n) begin
      dp_r <= {65{1'b0}};
      dp_abs_r <= {65{1'b0}};
      dp_pos_r <= 1'b0;
      dp_neg_r <= 1'b0;
    end else if (state == S_DIFF) begin
      dp_r <= dp;
      dp_abs_r <= dp_abs;
      dp_pos_r <= dp_pos;
      dp_neg_r <= dp_neg;
    end else begin
      dp_r <= dp_r;
      dp_abs_r <= dp_abs_r;
      dp_pos_r <= dp_pos_r;
      dp_neg_r <= dp_neg_r;
    end
  end

  wire acc_clr, acc_en;
  wire signed [80:0] sd_q, ad_q;
  wire signed [80:0] sd_nxt, ad_nxt;

  signed_accumulator #(.W(81)) u_sd_acc (
    .clk     (clk),
    .rst_n   (rst_n),
    .clr     (acc_clr),
    .en      (acc_en),
    .d_i     ({{16{dp_r[64]}}, dp_r}),
    .q_o     (sd_q),
    .q_nxt_o (sd_nxt)
  );

  signed_accumulator #(.W(81)) u_ad_acc (
    .clk     (clk),
    .rst_n   (rst_n),
    .clr     (acc_clr),
    .en      (acc_en),
    .d_i     ({16'd0, dp_abs_r}),
    .q_o     (ad_q),
    .q_nxt_o (ad_nxt)
  );

  assign sd_hi_o = sd_q[80:49];

  wire [80:0] sd_nxt_abs;

  abs_value #(.W(81)) u_sd_abs (
    .a_i (sd_nxt),
    .y_o (sd_nxt_abs)
  );

  wire [80:0] ad_nxt_shift = ad_nxt >> lambda_r;

  (* mark_debug = "true" *) reg [80:0] sd_abs_r;
  (* mark_debug = "true" *) reg [80:0] ad_shift_r;

  always @(posedge clk) begin
    if (!rst_n) begin
      sd_abs_r <= {81{1'b0}};
      ad_shift_r <= {81{1'b0}};
    end else if (state == S_CERT) begin
      sd_abs_r <= sd_nxt_abs;
      ad_shift_r <= ad_nxt_shift;
    end else begin
      sd_abs_r <= sd_abs_r;
      ad_shift_r <= ad_shift_r;
    end
  end

  wire cert_gt;

  value_comparator #(.W(81)) u_cert_cmp (
    .a_i         (sd_abs_r),
    .b_i         (ad_shift_r),
    .is_signed_i (1'b0),
    .gt_o        (cert_gt),
    .ge_o        (),
    .eq_o        ()
  );

  wire certified = cert_gt & (m_q >= m_min_r);
  wire race_exhausted = (m_q >= m_max_r);

  wire signed [33:0] delta;

  sign_step #(.W(34)) u_sign_step (
    .pos_i   (dp_pos_r),
    .neg_i   (dp_neg_r),
    .step_i  ({2'b00, a_val}),
    .delta_o (delta)
  );

  wire [33:0] x_step_clip;

  range_clip #(.W(34)) u_x_clip (
    .a_i         ({2'b00, x} + delta),
    .lo_i        ({2'b00, f_lo_r}),
    .hi_i        ({2'b00, f_hi_r}),
    .is_signed_i (1'b1),
    .y_o         (x_step_clip)
  );

  wire a_ge_min;

  value_comparator #(.W(32)) u_minstep_cmp (
    .a_i         (a_val),
    .b_i         (min_step_r),
    .is_signed_i (1'b0),
    .gt_o        (),
    .ge_o        (a_ge_min),
    .eq_o        ()
  );

  wire a_lt_min = ~a_ge_min;

  wire pat_clr, pat_step, pat_hit;
  wire pat_conv;

  conv_patience #(.W(8)) u_patience (
    .clk        (clk),
    .rst_n      (rst_n),
    .clr        (pat_clr),
    .step_i     (pat_step),
    .hit_i      (pat_hit),
    .patience_i (patience_r),
    .conv_o     (pat_conv)
  );

  assign k_clr = (state == S_IDLE) & start;
  assign k_en = (state == S_STEP) | (state == S_TIE);
  assign m_clr = (state == S_PAIR_INIT);
  assign m_en = (state == S_CERT);
  assign acc_clr = (state == S_PAIR_INIT);
  assign acc_en = (state == S_CERT);
  assign pat_clr = (state == S_IDLE) & start;
  assign pat_step = (state == S_STEP) | (state == S_TIE);
  assign pat_hit = (state == S_TIE) ? 1'b1 : (use_lut_r & a_lt_min);

  always @(posedge clk) begin
    if (!rst_n)
      state <= S_IDLE;
    else
      state <= next_state;
  end

  always @(*) begin
    case (state)
      S_IDLE:
        next_state = start ? S_PAIR_INIT : S_IDLE;

      S_PAIR_INIT:
        next_state = S_PRESENT_A;

      S_PRESENT_A:
        next_state = freq_ack_i ? S_MEAS_A : S_PRESENT_A;

      S_MEAS_A:
        next_state = amp_valid_i ? S_PRESENT_B : S_MEAS_A;

      S_PRESENT_B:
        next_state = freq_ack_i ? S_MEAS_B : S_PRESENT_B;

      S_MEAS_B:
        next_state = amp_valid_i ? S_DIFF : S_MEAS_B;

      S_DIFF:
        next_state = S_CERT;

      S_CERT:
        next_state = S_DECIDE;

      S_DECIDE: begin
        if (use_lut_r)
          next_state = S_STEP;
        else if (certified)
          next_state = S_STEP;
        else if (race_exhausted)
          next_state = S_TIE;
        else
          next_state = S_PRESENT_A;
      end

      S_STEP:
        next_state = S_CONV_CHK;

      S_TIE:
        next_state = S_CONV_CHK;

      S_CONV_CHK: begin
        if (pat_conv)
          next_state = S_DONE;
        else if (k_q >= max_iter_r)
          next_state = S_DONE;
        else
          next_state = S_PAIR_INIT;
      end

      S_DONE:
        next_state = S_IDLE;

      default:
        next_state = S_IDLE;
    endcase
  end

  always @(posedge clk) begin
    if (!rst_n) begin
      kw_mode_r <= 1'b0;
      use_lut_r <= 1'b0;
      dip_r <= 1'b0;
      f_lo_r <= 32'd0;
      f_hi_r <= 32'hFFFFFFFF;
      fstep_r <= 32'd0;
      min_step_r <= 32'd0;
      max_iter_r <= 16'd0;
      m_min_r <= 16'd1;
      m_max_r <= 16'd1;
      patience_r <= 8'd0;
      lambda_r <= 5'd0;
    end else if ((state == S_IDLE) & start) begin
      kw_mode_r <= kw_mode_i;
      use_lut_r <= use_lut_i;
      dip_r <= dip_i;
      f_lo_r <= f_lo_i;
      f_hi_r <= f_hi_i;
      fstep_r <= fstep_i;
      min_step_r <= min_step_i;
      max_iter_r <= (max_iter_i == 16'd0) ? 16'd1 : max_iter_i;
      m_min_r <= (m_min_i == 16'd0) ? 16'd1 : m_min_i;
      m_max_r <= (m_max_i == 16'd0) ? 16'd1 : m_max_i;
      patience_r <= patience_i;
      lambda_r <= lambda_i;
    end else begin
      kw_mode_r <= kw_mode_r;
      use_lut_r <= use_lut_r;
      dip_r <= dip_r;
      f_lo_r <= f_lo_r;
      f_hi_r <= f_hi_r;
      fstep_r <= fstep_r;
      min_step_r <= min_step_r;
      max_iter_r <= max_iter_r;
      m_min_r <= m_min_r;
      m_max_r <= m_max_r;
      patience_r <= patience_r;
      lambda_r <= lambda_r;
    end
  end

  always @(posedge clk) begin
    if (!rst_n) begin
      x <= 32'd0;
      p_a_r <= 64'd0;
      p_b_r <= 64'd0;
      freq_word_o <= 32'd0;
      freq_valid_o <= 1'b0;
      probe_arm_o <= 1'b0;
      busy_o <= 1'b0;
      done_o <= 1'b0;
      converged_o <= 1'b0;
      capped_o <= 1'b0;
    end else begin
      case (state)
      S_IDLE: begin
        freq_word_o <= freq_word_o;
        freq_valid_o <= 1'b0;
        probe_arm_o <= 1'b0;
        done_o <= 1'b0;
        p_a_r <= p_a_r;
        p_b_r <= p_b_r;
        if (start) begin
          x <= x0_i;
          busy_o <= 1'b1;
          converged_o <= 1'b0;
          capped_o <= 1'b0;
        end else begin
          x <= x;
          busy_o <= busy_o;
          converged_o <= converged_o;
          capped_o <= capped_o;
        end
      end

      S_PAIR_INIT: begin
        x <= x;
        p_a_r <= p_a_r;
        p_b_r <= p_b_r;
        freq_word_o <= freq_word_o;
        freq_valid_o <= freq_valid_o;
        probe_arm_o <= 1'b0;
        busy_o <= busy_o;
        done_o <= 1'b0;
        converged_o <= converged_o;
        capped_o <= capped_o;
      end

      S_PRESENT_A: begin
        x <= x;
        p_a_r <= p_a_r;
        p_b_r <= p_b_r;
        freq_word_o <= probe_a;
        freq_valid_o <= freq_ack_i ? 1'b0 : 1'b1;
        probe_arm_o <= freq_ack_i;
        busy_o <= busy_o;
        done_o <= 1'b0;
        converged_o <= converged_o;
        capped_o <= capped_o;
      end

      S_MEAS_A: begin
        x <= x;
        p_b_r <= p_b_r;
        freq_word_o <= freq_word_o;
        freq_valid_o <= freq_valid_o;
        probe_arm_o <= 1'b0;
        busy_o <= busy_o;
        done_o <= 1'b0;
        converged_o <= converged_o;
        capped_o <= capped_o;
        if (amp_valid_i)
          p_a_r <= amp_data_i;
        else
          p_a_r <= p_a_r;
      end

      S_PRESENT_B: begin
        x <= x;
        p_a_r <= p_a_r;
        p_b_r <= p_b_r;
        freq_word_o <= probe_b;
        freq_valid_o <= freq_ack_i ? 1'b0 : 1'b1;
        probe_arm_o <= freq_ack_i;
        busy_o <= busy_o;
        done_o <= 1'b0;
        converged_o <= converged_o;
        capped_o <= capped_o;
      end

      S_MEAS_B: begin
        x <= x;
        p_a_r <= p_a_r;
        freq_word_o <= freq_word_o;
        freq_valid_o <= freq_valid_o;
        probe_arm_o <= 1'b0;
        busy_o <= busy_o;
        done_o <= 1'b0;
        converged_o <= converged_o;
        capped_o <= capped_o;
        if (amp_valid_i)
          p_b_r <= amp_data_i;
        else
          p_b_r <= p_b_r;
      end

      S_DIFF: begin
        x <= x;
        p_a_r <= p_a_r;
        p_b_r <= p_b_r;
        freq_word_o <= freq_word_o;
        freq_valid_o <= freq_valid_o;
        probe_arm_o <= 1'b0;
        busy_o <= busy_o;
        done_o <= 1'b0;
        converged_o <= converged_o;
        capped_o <= capped_o;
      end

      S_CERT: begin
        x <= x;
        p_a_r <= p_a_r;
        p_b_r <= p_b_r;
        freq_word_o <= freq_word_o;
        freq_valid_o <= freq_valid_o;
        probe_arm_o <= 1'b0;
        busy_o <= busy_o;
        done_o <= 1'b0;
        converged_o <= converged_o;
        capped_o <= capped_o;
      end

      S_DECIDE: begin
        x <= x;
        p_a_r <= p_a_r;
        p_b_r <= p_b_r;
        freq_word_o <= freq_word_o;
        freq_valid_o <= freq_valid_o;
        probe_arm_o <= 1'b0;
        busy_o <= busy_o;
        done_o <= 1'b0;
        converged_o <= converged_o;
        capped_o <= capped_o;
      end

      S_STEP: begin
        x <= x_step_clip[31:0];
        p_a_r <= p_a_r;
        p_b_r <= p_b_r;
        freq_word_o <= freq_word_o;
        freq_valid_o <= freq_valid_o;
        probe_arm_o <= 1'b0;
        busy_o <= busy_o;
        done_o <= 1'b0;
        converged_o <= converged_o;
        capped_o <= capped_o;
      end

      S_TIE: begin
        x <= x;
        p_a_r <= p_a_r;
        p_b_r <= p_b_r;
        freq_word_o <= freq_word_o;
        freq_valid_o <= freq_valid_o;
        probe_arm_o <= 1'b0;
        busy_o <= busy_o;
        done_o <= 1'b0;
        converged_o <= converged_o;
        capped_o <= capped_o;
      end

      S_CONV_CHK: begin
        x <= x;
        p_a_r <= p_a_r;
        p_b_r <= p_b_r;
        freq_word_o <= freq_word_o;
        freq_valid_o <= freq_valid_o;
        probe_arm_o <= 1'b0;
        busy_o <= busy_o;
        done_o <= 1'b0;
        if (pat_conv) begin
          converged_o <= 1'b1;
          capped_o <= capped_o;
        end else if (k_q >= max_iter_r) begin
          converged_o <= converged_o;
          capped_o <= 1'b1;
        end else begin
          converged_o <= converged_o;
          capped_o <= capped_o;
        end
      end

      S_DONE: begin
        x <= x;
        p_a_r <= p_a_r;
        p_b_r <= p_b_r;
        freq_word_o <= freq_word_o;
        freq_valid_o <= freq_valid_o;
        probe_arm_o <= 1'b0;
        busy_o <= 1'b0;
        done_o <= 1'b1;
        converged_o <= converged_o;
        capped_o <= capped_o;
      end

      default: begin
        x <= x;
        p_a_r <= p_a_r;
        p_b_r <= p_b_r;
        freq_word_o <= freq_word_o;
        freq_valid_o <= 1'b0;
        probe_arm_o <= 1'b0;
        busy_o <= busy_o;
        done_o <= 1'b0;
        converged_o <= converged_o;
        capped_o <= capped_o;
      end
      endcase
    end
  end

  (* mark_debug = "true" *) reg start_dbg;
  (* mark_debug = "true" *) reg freq_ack_dbg;
  (* mark_debug = "true" *) reg amp_valid_dbg;
  (* mark_debug = "true" *) reg [63:0] amp_data_dbg;
  (* mark_debug = "true" *) reg [3:0] next_state_dbg;
  (* mark_debug = "true" *) reg [15:0] k_q_dbg;
  (* mark_debug = "true" *) reg [15:0] m_q_dbg;
  (* mark_debug = "true" *) reg [31:0] a_val_dbg;
  (* mark_debug = "true" *) reg [31:0] c_val_dbg;
  (* mark_debug = "true" *) reg [31:0] x_plus_dbg;
  (* mark_debug = "true" *) reg [31:0] x_minus_dbg;
  (* mark_debug = "true" *) reg signed [80:0] sd_q_dbg;
  (* mark_debug = "true" *) reg signed [80:0] ad_q_dbg;
  (* mark_debug = "true" *) reg cert_gt_dbg;
  (* mark_debug = "true" *) reg certified_dbg;
  (* mark_debug = "true" *) reg race_exhausted_dbg;
  (* mark_debug = "true" *) reg signed [33:0] delta_dbg;
  (* mark_debug = "true" *) reg [33:0] x_step_clip_dbg;
  (* mark_debug = "true" *) reg a_lt_min_dbg;
  (* mark_debug = "true" *) reg pat_hit_dbg;
  (* mark_debug = "true" *) reg pat_conv_dbg;
  always @(posedge clk) begin
    if (!rst_n) begin
      start_dbg <= 1'b0;
      freq_ack_dbg <= 1'b0;
      amp_valid_dbg <= 1'b0;
      amp_data_dbg <= 64'd0;
      next_state_dbg <= 4'd0;
      k_q_dbg <= 16'd0;
      m_q_dbg <= 16'd0;
      a_val_dbg <= 32'd0;
      c_val_dbg <= 32'd0;
      x_plus_dbg <= 32'd0;
      x_minus_dbg <= 32'd0;
      sd_q_dbg <= {81{1'b0}};
      ad_q_dbg <= {81{1'b0}};
      cert_gt_dbg <= 1'b0;
      certified_dbg <= 1'b0;
      race_exhausted_dbg <= 1'b0;
      delta_dbg <= {34{1'b0}};
      x_step_clip_dbg <= {34{1'b0}};
      a_lt_min_dbg <= 1'b0;
      pat_hit_dbg <= 1'b0;
      pat_conv_dbg <= 1'b0;
    end else begin
      start_dbg <= start;
      freq_ack_dbg <= freq_ack_i;
      amp_valid_dbg <= amp_valid_i;
      amp_data_dbg <= amp_data_i;
      next_state_dbg <= next_state;
      k_q_dbg <= k_q;
      m_q_dbg <= m_q;
      a_val_dbg <= a_val;
      c_val_dbg <= c_val;
      x_plus_dbg <= x_plus;
      x_minus_dbg <= x_minus;
      sd_q_dbg <= sd_q;
      ad_q_dbg <= ad_q;
      cert_gt_dbg <= cert_gt;
      certified_dbg <= certified;
      race_exhausted_dbg <= race_exhausted;
      delta_dbg <= delta;
      x_step_clip_dbg <= x_step_clip;
      a_lt_min_dbg <= a_lt_min;
      pat_hit_dbg <= pat_hit;
      pat_conv_dbg <= pat_conv;
    end
  end

endmodule
