`timescale 1ns / 1ps

module amp_calc #(
  parameter POW2_DIV_ONLY = 0
) (
  input wire clk,
  input wire rst_n,

  input wire s_axis_tvalid,
  input wire s_axis_tready,
  input wire [63:0] s_axis_tdata,

  input wire arm_i,
  input wire [31:0] averager_value_i,
  input wire [31:0] nsamp_i,
  input wire [31:0] n0_i,
  input wire [31:0] n_min_i,

  input wire [2:0] reduce_sel_i,
  input wire prescale_en_i,
  input wire estop_en_i,
  input wire estop_hold_i,
  input wire [1:0] estop_sel_i,
  input wire [3:0] m_i,
  input wire ckmon_i,
  input wire [1:0] dens_i,
  input wire [2:0] confirm_i,
  input wire [5:0] cap_kp1_i,
  input wire [53:0] cap_mag_i,
  input wire [4:0] cap_sft_i,

  input wire thr_wr_en_i,
  input wire [4:0] thr_wr_addr_i,
  input wire [45:0] thr_wr_data_i,

  output wire warmup_done_o,
  output wire early_stop_o,
  output wire early_pulse_o,
  output wire [31:0] n_used_o,
  output wire [45:0] dev_acc_o,

  output wire [31:0] mean_i_o,
  output wire [31:0] mean_q_o,
  output wire log_wr_o,
  output wire [15:0] log_entry_o,
  output wire drift_o,

  output wire [63:0] power_o,
  output wire power_valid_o
);

  (* mark_debug = "true" *) reg signed [31:0] i_in;
  (* mark_debug = "true" *) reg signed [31:0] q_in;
  (* mark_debug = "true" *) reg v_in;
  (* mark_debug = "true" *) reg r_in;

  always @(posedge clk) begin
    if (!rst_n) begin
      i_in <= 32'd0;
      q_in <= 32'd0;
      v_in <= 1'b0;
      r_in <= 1'b0;
    end else begin
      i_in <= s_axis_tdata[31:0];
      q_in <= s_axis_tdata[63:32];
      v_in <= s_axis_tvalid;
      r_in <= s_axis_tready;
    end
  end

  wire [1:0] dens_eff = (POW2_DIV_ONLY != 0) ? 2'd0 : dens_i;

  wire [4:0] s1_w;
  wire [4:0] s2_w;

  log2_floor u_log2_nsamp (
    .v_i (nsamp_i),
    .y_o (s1_w)
  );

  log2_floor u_log2_avg (
    .v_i (averager_value_i),
    .y_o (s2_w)
  );

  (* mark_debug = "true" *) reg [4:0] s1_r;
  (* mark_debug = "true" *) reg [4:0] s2_r;
  (* mark_debug = "true" *) reg [2:0] red_sel_r;
  (* mark_debug = "true" *) reg [1:0] es_sel_r;
  reg ckmon_r;

  always @(posedge clk) begin
    if (!rst_n) begin
      s1_r <= 5'd0;
      s2_r <= 5'd0;
      red_sel_r <= 3'd0;
      es_sel_r <= 2'd0;
      ckmon_r <= 1'b0;
    end else if (arm_i) begin
      s1_r <= prescale_en_i ? s1_w : 5'd0;
      s2_r <= s2_w;
      red_sel_r <= reduce_sel_i;
      es_sel_r <= estop_sel_i;
      ckmon_r <= ckmon_i;
    end else begin
      s1_r <= s1_r;
      s2_r <= s2_r;
      red_sel_r <= red_sel_r;
      es_sel_r <= es_sel_r;
      ckmon_r <= ckmon_r;
    end
  end

  wire signed [32:0] i_in_ext = {i_in[31], i_in};
  wire signed [32:0] q_in_ext = {q_in[31], q_in};

  wire signed [32:0] xs_i;
  wire signed [32:0] xs_q;

  round_shift #(.W(33)) u_prescale_i (
    .d_i  (i_in_ext),
    .sh_i (s1_r),
    .y_o  (xs_i)
  );

  round_shift #(.W(33)) u_prescale_q (
    .d_i  (q_in_ext),
    .sh_i (s1_r),
    .y_o  (xs_q)
  );

  wire shot_v = v_in & r_in;

  (* mark_debug = "true" *) reg signed [32:0] xs_i_r;
  (* mark_debug = "true" *) reg signed [32:0] xs_q_r;
  (* mark_debug = "true" *) reg shot_v_r;

  always @(posedge clk) begin
    if (!rst_n) begin
      xs_i_r <= {33{1'b0}};
      xs_q_r <= {33{1'b0}};
      shot_v_r <= 1'b0;
    end else begin
      xs_i_r <= xs_i;
      xs_q_r <= xs_q;
      shot_v_r <= shot_v;
    end
  end

  wire signed [17:0] x_i = xs_i_r[17:0];
  wire signed [17:0] x_q = xs_q_r[17:0];

  wire seq_first;
  wire [31:0] seq_n;
  (* max_fanout = 64 *) wire acc_clr;
  (* max_fanout = 64 *) wire acc_en;
  wire is_last;
  wire stop_now;
  wire stop_np_now;
  wire point_latch;
  wire emit;
  wire es_stop;
  wire np_stop_mux;
  wire [31:0] np_n_mux;

  shot_sequencer u_shot_sequencer (
    .clk               (clk),
    .rst_n             (rst_n),
    .arm_i             (arm_i),
    .shot_i            (shot_v_r),
    .averager_value_i  (averager_value_i),
    .n0_i              (n0_i),
    .stop_i            (es_stop),
    .stop_hold_i       (estop_hold_i),
    .stop_np_i         (np_stop_mux),
    .n_np_i            (np_n_mux),
    .armed_o           (),
    .stopped_o         (),
    .first_o           (seq_first),
    .n_o               (seq_n),
    .acc_clr_o         (acc_clr),
    .acc_en_o          (acc_en),
    .is_last_o         (is_last),
    .stop_now_o        (stop_now),
    .stop_np_now_o     (stop_np_now),
    .point_latch_o     (point_latch),
    .emit_o            (emit),
    .warmup_done_o     (warmup_done_o),
    .early_o           (early_stop_o),
    .n_used_o          (n_used_o)
  );

  assign early_pulse_o = (stop_now | stop_np_now) & ~estop_hold_i;

  wire signed [63:0] acc_i_d = {{31{xs_i_r[32]}}, xs_i_r};
  wire signed [63:0] acc_q_d = {{31{xs_q_r[32]}}, xs_q_r};

  wire signed [63:0] acc_i_q;
  wire signed [63:0] acc_q_q;
  wire signed [63:0] acc_i_nxt;
  wire signed [63:0] acc_q_nxt;

  signed_accumulator #(.W(64)) u_acc_i (
    .clk     (clk),
    .rst_n   (rst_n),
    .clr     (acc_clr),
    .en      (acc_en),
    .d_i     (acc_i_d),
    .q_o     (acc_i_q),
    .q_nxt_o (acc_i_nxt)
  );

  signed_accumulator #(.W(64)) u_acc_q (
    .clk     (clk),
    .rst_n   (rst_n),
    .clr     (acc_clr),
    .en      (acc_en),
    .d_i     (acc_q_d),
    .q_o     (acc_q_q),
    .q_nxt_o (acc_q_nxt)
  );

  wire d_sub = ~seq_n[0];

  wire signed [63:0] dacc_i_nxt;
  wire signed [63:0] dacc_q_nxt;

  signed_diff_accumulator #(.W(64)) u_dacc_i (
    .clk     (clk),
    .rst_n   (rst_n),
    .clr     (acc_clr),
    .en      (acc_en),
    .sub_i   (d_sub),
    .d_i     (acc_i_d),
    .q_nxt_o (dacc_i_nxt)
  );

  signed_diff_accumulator #(.W(64)) u_dacc_q (
    .clk     (clk),
    .rst_n   (rst_n),
    .clr     (acc_clr),
    .en      (acc_en),
    .sub_i   (d_sub),
    .d_i     (acc_q_d),
    .q_nxt_o (dacc_q_nxt)
  );

  wire signed [17:0] mean_i_nxt;
  wire signed [17:0] mean_q_nxt;

  running_mean #(.MW(18), .RW(37)) u_mean_i (
    .clk        (clk),
    .rst_n      (rst_n),
    .clr        (acc_clr),
    .en         (acc_en),
    .first_i    (seq_first),
    .n_i        (seq_n),
    .x_i        (x_i),
    .mean_nxt_o (mean_i_nxt)
  );

  running_mean #(.MW(18), .RW(37)) u_mean_q (
    .clk        (clk),
    .rst_n      (rst_n),
    .clr        (acc_clr),
    .en         (acc_en),
    .first_i    (seq_first),
    .n_i        (seq_n),
    .x_i        (x_q),
    .mean_nxt_o (mean_q_nxt)
  );

  wire [4:0] es_j;
  wire [4:0] shift_amt = is_last ? s2_r : es_j;

  wire signed [49:0] acc_i_red = acc_i_nxt[49:0];
  wire signed [49:0] acc_q_red = acc_q_nxt[49:0];

  wire signed [49:0] red_i;
  wire signed [49:0] red_q;

  round_shift #(.W(50)) u_reduce_i (
    .d_i  (acc_i_red),
    .sh_i (shift_amt),
    .y_o  (red_i)
  );

  round_shift #(.W(50)) u_reduce_q (
    .d_i  (acc_q_red),
    .sh_i (shift_amt),
    .y_o  (red_q)
  );

  wire mad_en = estop_en_i & (es_sel_r == 2'd0);

  early_stop_mad u_early_stop_mad (
    .clk           (clk),
    .rst_n         (rst_n),
    .arm_i         (arm_i),
    .en_i          (mad_en),
    .fold_i        (acc_en),
    .first_i       (seq_first),
    .n_i           (seq_n),
    .n_min_i       (n_min_i),
    .x_i_i         (x_i),
    .x_q_i         (x_q),
    .mean_ep_i_i   (red_i[17:0]),
    .mean_ep_q_i   (red_q[17:0]),
    .thr_wr_en_i   (thr_wr_en_i),
    .thr_wr_addr_i (thr_wr_addr_i),
    .thr_wr_data_i (thr_wr_data_i),
    .j_o           (es_j),
    .stop_o        (es_stop),
    .dev_acc_o     (dev_acc_o)
  );

  wire grid_en = estop_en_i & (es_sel_r == 2'd1);
  wire ckdiff_en = estop_en_i & (es_sel_r == 2'd2);

  reg signed [63:0] p_i_r;
  reg signed [63:0] p_q_r;

  wire grid_stop;
  wire [31:0] grid_n;
  wire [4:0] grid_j;
  wire [1:0] grid_midx;
  wire grid_sat;
  wire grid_d1;

  estop_split u_estop_grid (
    .clk       (clk),
    .rst_n     (rst_n),
    .arm_i     (arm_i),
    .en_i      (grid_en),
    .fold_i    (acc_en),
    .n_i       (seq_n),
    .n_min_i   (n_min_i),
    .m_i       (m_i),
    .dens_i    (dens_eff),
    .confirm_i (confirm_i),
    .d_i_i     (dacc_i_nxt),
    .d_q_i     (dacc_q_nxt),
    .s_i_i     (acc_i_nxt),
    .s_q_i     (acc_q_nxt),
    .stop_o    (grid_stop),
    .np_n_o    (grid_n),
    .j_o       (grid_j),
    .midx_o    (grid_midx),
    .sat_o     (grid_sat),
    .at_d1_o   (grid_d1)
  );

  wire ckdiff_stop;
  wire [31:0] ckdiff_n;
  wire [4:0] ckdiff_k;
  wire ckdiff_pass;
  wire ckdiff_sat;
  wire ckdiff_d1;

  estop_ckdiff u_estop_ckdiff (
    .clk     (clk),
    .rst_n   (rst_n),
    .arm_i   (arm_i),
    .en_i    (ckdiff_en),
    .fold_i  (acc_en),
    .n_i     (seq_n),
    .n_min_i (n_min_i),
    .m_i     (m_i),
    .s_i_i   (acc_i_nxt),
    .s_q_i   (acc_q_nxt),
    .p_i_i   (p_i_r),
    .p_q_i   (p_q_r),
    .stop_o  (ckdiff_stop),
    .np_n_o  (ckdiff_n),
    .k_o     (ckdiff_k),
    .pass_o  (ckdiff_pass),
    .sat_o   (ckdiff_sat),
    .at_d1_o (ckdiff_d1)
  );

  assign np_stop_mux = (es_sel_r == 2'd1) ? grid_stop :
                       (es_sel_r == 2'd2) ? ckdiff_stop : 1'b0;
  assign np_n_mux = (es_sel_r == 2'd1) ? grid_n :
                    (es_sel_r == 2'd2) ? ckdiff_n : 32'd0;

  wire [4:0] np_j_mux = (es_sel_r == 2'd1) ? grid_j :
                        (es_sel_r == 2'd2) ? ckdiff_k : 5'd0;
  wire [1:0] np_midx_mux = (es_sel_r == 2'd1) ? grid_midx : 2'd0;
  wire np_sat_mux = (es_sel_r == 2'd1) ? grid_sat :
                    (es_sel_r == 2'd2) ? ckdiff_sat : 1'b0;

  wire at_d1_mux = (es_sel_r == 2'd1) ? grid_d1 :
                   (es_sel_r == 2'd2) ? ckdiff_d1 : 1'b0;

  always @(posedge clk) begin
    if (!rst_n) begin
      p_i_r <= {64{1'b0}};
      p_q_r <= {64{1'b0}};
    end else if (arm_i) begin
      p_i_r <= {64{1'b0}};
      p_q_r <= {64{1'b0}};
    end else if (at_d1_mux) begin
      p_i_r <= acc_i_q;
      p_q_r <= acc_q_q;
    end else begin
      p_i_r <= p_i_r;
      p_q_r <= p_q_r;
    end
  end

  (* mark_debug = "true" *) reg drift_r;

  wire drift_hit = stop_np_now & ckmon_r & (es_sel_r == 2'd1) & ~ckdiff_pass;

  always @(posedge clk) begin
    if (!rst_n)
      drift_r <= 1'b0;
    else if (arm_i)
      drift_r <= 1'b0;
    else if (drift_hit)
      drift_r <= 1'b1;
    else
      drift_r <= drift_r;
  end

  assign drift_o = drift_r;

  wire sel3 = (red_sel_r == 3'd3);
  wire trig_np = stop_np_now & sel3;
  wire trig_cap = emit & sel3 & ~stop_np_now;

  wire [53:0] rom_mag = (POW2_DIV_ONLY != 0) ? 54'd4503599627370496 :
                        (np_midx_mux == 2'd1) ? 54'd3002399751580331 :
                        (np_midx_mux == 2'd2) ? 54'd3602879701896397 :
                        (np_midx_mux == 2'd3) ? 54'd5146971002709139 : 54'd4503599627370496;

  wire [4:0] rom_sft = (POW2_DIV_ONLY != 0) ? 5'd0 : {3'd0, np_midx_mux};

  reg signed [63:0] num_i_r;
  reg signed [63:0] num_q_r;
  reg [31:0] den_r;
  reg [5:0] kp1_r;
  reg [53:0] mag_r;
  reg [4:0] sft_r;
  reg [2:0] typ_r;
  reg [4:0] k_r;
  reg conv_r;
  reg satl_r;
  reg driftl_r;
  reg pend_r;

  always @(posedge clk) begin
    if (!rst_n) begin
      num_i_r <= {64{1'b0}};
      num_q_r <= {64{1'b0}};
      den_r <= 32'd1;
      kp1_r <= 6'd1;
      mag_r <= 54'd4503599627370496;
      sft_r <= 5'd0;
      typ_r <= 3'd0;
      k_r <= 5'd0;
      conv_r <= 1'b0;
      satl_r <= 1'b0;
      driftl_r <= 1'b0;
      pend_r <= 1'b0;
    end else if (arm_i) begin
      num_i_r <= num_i_r;
      num_q_r <= num_q_r;
      den_r <= den_r;
      kp1_r <= kp1_r;
      mag_r <= mag_r;
      sft_r <= sft_r;
      typ_r <= typ_r;
      k_r <= k_r;
      conv_r <= conv_r;
      satl_r <= satl_r;
      driftl_r <= driftl_r;
      pend_r <= 1'b0;
    end else if (trig_np) begin
      num_i_r <= p_i_r;
      num_q_r <= p_q_r;
      den_r <= np_n_mux;
      kp1_r <= {1'b0, np_j_mux} + 6'd1;
      mag_r <= rom_mag;
      sft_r <= rom_sft;
      typ_r <= {1'b0, np_midx_mux};
      k_r <= np_j_mux;
      conv_r <= 1'b1;
      satl_r <= np_sat_mux;
      driftl_r <= drift_r | drift_hit;
      pend_r <= estop_hold_i;
    end else if (trig_cap) begin
      pend_r <= 1'b0;
      if (pend_r) begin
        num_i_r <= num_i_r;
        num_q_r <= num_q_r;
        den_r <= den_r;
        kp1_r <= kp1_r;
        mag_r <= mag_r;
        sft_r <= sft_r;
        typ_r <= typ_r;
        k_r <= k_r;
        conv_r <= conv_r;
        satl_r <= satl_r;
        driftl_r <= driftl_r;
      end else begin
        num_i_r <= acc_i_nxt;
        num_q_r <= acc_q_nxt;
        den_r <= seq_n;
        kp1_r <= cap_kp1_i;
        mag_r <= cap_mag_i;
        sft_r <= cap_sft_i;
        typ_r <= 3'd4;
        k_r <= 5'd0;
        conv_r <= 1'b0;
        satl_r <= np_sat_mux;
        driftl_r <= drift_r;
      end
    end else begin
      num_i_r <= num_i_r;
      num_q_r <= num_q_r;
      den_r <= den_r;
      kp1_r <= kp1_r;
      mag_r <= mag_r;
      sft_r <= sft_r;
      typ_r <= typ_r;
      k_r <= k_r;
      conv_r <= conv_r;
      satl_r <= satl_r;
      driftl_r <= driftl_r;
      pend_r <= pend_r;
    end
  end

  localparam [2:0] R_IDLE = 3'd0, R_STARTI = 3'd1, R_STARTQ = 3'd2, R_WAIT = 3'd3, R_FIN = 3'd4;

  reg [2:0] r_state;
  reg [2:0] r_next;

  wire go = (trig_np & ~estop_hold_i) | trig_cap;

  wire gm_done;
  wire signed [31:0] gm_q;
  reg din_i;
  reg signed [31:0] div_i_q_r;

  wire both_done = din_i & gm_done;

  always @(posedge clk) begin
    if (!rst_n)
      r_state <= R_IDLE;
    else
      r_state <= r_next;
  end

  always @(*) begin
    case (r_state)
      R_IDLE:
        r_next = go ? R_STARTI : R_IDLE;

      R_STARTI:
        r_next = R_STARTQ;

      R_STARTQ:
        r_next = R_WAIT;

      R_WAIT:
        r_next = both_done ? R_FIN : R_WAIT;

      R_FIN:
        r_next = R_IDLE;

      default:
        r_next = R_IDLE;
    endcase
  end

  always @(posedge clk) begin
    if (!rst_n) begin
      din_i <= 1'b0;
      div_i_q_r <= 32'd0;
    end else if (r_state == R_STARTI) begin
      din_i <= 1'b0;
      div_i_q_r <= div_i_q_r;
    end else if (gm_done & ~din_i) begin
      din_i <= 1'b1;
      div_i_q_r <= gm_q;
    end else begin
      din_i <= din_i;
      div_i_q_r <= div_i_q_r;
    end
  end

  wire gm_start = (r_state == R_STARTI) | (r_state == R_STARTQ);
  wire signed [63:0] gm_num = (r_state == R_STARTI) ? num_i_r : num_q_r;
  wire retire_fin = (r_state == R_FIN);

  gm_divider #(.POW2_ONLY(POW2_DIV_ONLY)) u_gm_divider (
    .clk     (clk),
    .rst_n   (rst_n),
    .start_i (gm_start),
    .num_i   (gm_num),
    .den_i   (den_r),
    .kp1_i   (kp1_r),
    .mag_i   (mag_r),
    .sft_i   (sft_r),
    .busy_o  (),
    .done_o  (gm_done),
    .q_o     (gm_q)
  );

  reg [31:0] mean_i_r;
  reg [31:0] mean_q_r;

  always @(posedge clk) begin
    if (!rst_n) begin
      mean_i_r <= 32'd0;
      mean_q_r <= 32'd0;
    end else if (retire_fin) begin
      mean_i_r <= div_i_q_r;
      mean_q_r <= gm_q;
    end else begin
      mean_i_r <= mean_i_r;
      mean_q_r <= mean_q_r;
    end
  end

  assign mean_i_o = mean_i_r;
  assign mean_q_o = mean_q_r;
  assign log_wr_o = retire_fin;
  assign log_entry_o = {5'd0, driftl_r, satl_r, conv_r, k_r, typ_r};

  wire signed [31:0] pt_i_shift = {{14{red_i[17]}}, red_i[17:0]};
  wire signed [31:0] pt_q_shift = {{14{red_q[17]}}, red_q[17:0]};
  wire signed [31:0] pt_i_mean = {{14{mean_i_nxt[17]}}, mean_i_nxt};
  wire signed [31:0] pt_q_mean = {{14{mean_q_nxt[17]}}, mean_q_nxt};

  wire signed [31:0] pt_i_new = (red_sel_r == 3'd1) ? pt_i_shift :
                                (red_sel_r == 3'd2) ? pt_i_mean : {32{1'b0}};
  wire signed [31:0] pt_q_new = (red_sel_r == 3'd1) ? pt_q_shift :
                                (red_sel_r == 3'd2) ? pt_q_mean : {32{1'b0}};

  (* mark_debug = "true" *) reg signed [31:0] point_i;
  (* mark_debug = "true" *) reg signed [31:0] point_q;

  always @(posedge clk) begin
    if (!rst_n) begin
      point_i <= {32{1'b0}};
      point_q <= {32{1'b0}};
    end else if (retire_fin) begin
      point_i <= div_i_q_r;
      point_q <= gm_q;
    end else if (point_latch) begin
      point_i <= pt_i_new;
      point_q <= pt_q_new;
    end else begin
      point_i <= point_i;
      point_q <= point_q;
    end
  end

  wire emit_direct = emit & ~sel3;

  power_macc u_power_macc (
    .clk     (clk),
    .rst_n   (rst_n),
    .start_i (emit_direct | retire_fin),
    .i_i     (point_i),
    .q_i     (point_q),
    .power_o (power_o),
    .valid_o (power_valid_o)
  );

  (* mark_debug = "true" *) reg arm_dbg;
  (* mark_debug = "true" *) reg signed [63:0] acc_i_nxt_dbg;
  (* mark_debug = "true" *) reg signed [63:0] acc_q_nxt_dbg;
  (* mark_debug = "true" *) reg signed [17:0] red_i_dbg;
  (* mark_debug = "true" *) reg signed [17:0] red_q_dbg;
  (* mark_debug = "true" *) reg signed [17:0] mean_i_nxt_dbg;
  (* mark_debug = "true" *) reg signed [17:0] mean_q_nxt_dbg;
  (* mark_debug = "true" *) reg [4:0] shift_amt_dbg;
  (* mark_debug = "true" *) reg [4:0] es_j_dbg;
  (* mark_debug = "true" *) reg es_stop_dbg;
  (* mark_debug = "true" *) reg thr_wr_en_dbg;
  (* mark_debug = "true" *) reg [4:0] thr_wr_addr_dbg;
  (* mark_debug = "true" *) reg [2:0] r_state_dbg;
  (* mark_debug = "true" *) reg trig_np_dbg;
  (* mark_debug = "true" *) reg trig_cap_dbg;
  (* mark_debug = "true" *) reg pend_dbg;
  (* mark_debug = "true" *) reg [31:0] den_dbg;
  (* mark_debug = "true" *) reg [5:0] kp1_dbg;
  (* mark_debug = "true" *) reg [4:0] sft_dbg;
  (* mark_debug = "true" *) reg retire_fin_dbg;
  (* mark_debug = "true" *) reg [31:0] mean_i_dbg;
  (* mark_debug = "true" *) reg [31:0] mean_q_dbg;
  (* mark_debug = "true" *) reg [15:0] log_entry_dbg;
  (* mark_debug = "true" *) reg grid_stop_dbg;
  (* mark_debug = "true" *) reg ckdiff_stop_dbg;
  (* mark_debug = "true" *) reg [31:0] np_n_dbg;
  (* mark_debug = "true" *) reg [4:0] np_j_dbg;
  (* mark_debug = "true" *) reg [1:0] np_midx_dbg;
  always @(posedge clk) begin
    if (!rst_n) begin
      arm_dbg <= 1'b0;
      acc_i_nxt_dbg <= {64{1'b0}};
      acc_q_nxt_dbg <= {64{1'b0}};
      red_i_dbg <= {18{1'b0}};
      red_q_dbg <= {18{1'b0}};
      mean_i_nxt_dbg <= {18{1'b0}};
      mean_q_nxt_dbg <= {18{1'b0}};
      shift_amt_dbg <= 5'd0;
      es_j_dbg <= 5'd0;
      es_stop_dbg <= 1'b0;
      thr_wr_en_dbg <= 1'b0;
      thr_wr_addr_dbg <= 5'd0;
      r_state_dbg <= 3'd0;
      trig_np_dbg <= 1'b0;
      trig_cap_dbg <= 1'b0;
      pend_dbg <= 1'b0;
      den_dbg <= 32'd0;
      kp1_dbg <= 6'd0;
      sft_dbg <= 5'd0;
      retire_fin_dbg <= 1'b0;
      mean_i_dbg <= 32'd0;
      mean_q_dbg <= 32'd0;
      log_entry_dbg <= 16'd0;
      grid_stop_dbg <= 1'b0;
      ckdiff_stop_dbg <= 1'b0;
      np_n_dbg <= 32'd0;
      np_j_dbg <= 5'd0;
      np_midx_dbg <= 2'd0;
    end else begin
      arm_dbg <= arm_i;
      acc_i_nxt_dbg <= acc_i_nxt;
      acc_q_nxt_dbg <= acc_q_nxt;
      red_i_dbg <= red_i[17:0];
      red_q_dbg <= red_q[17:0];
      mean_i_nxt_dbg <= mean_i_nxt;
      mean_q_nxt_dbg <= mean_q_nxt;
      shift_amt_dbg <= shift_amt;
      es_j_dbg <= es_j;
      es_stop_dbg <= es_stop;
      thr_wr_en_dbg <= thr_wr_en_i;
      thr_wr_addr_dbg <= thr_wr_addr_i;
      r_state_dbg <= r_state;
      trig_np_dbg <= trig_np;
      trig_cap_dbg <= trig_cap;
      pend_dbg <= pend_r;
      den_dbg <= den_r;
      kp1_dbg <= kp1_r;
      sft_dbg <= sft_r;
      retire_fin_dbg <= retire_fin;
      mean_i_dbg <= mean_i_r;
      mean_q_dbg <= mean_q_r;
      log_entry_dbg <= log_entry_o;
      grid_stop_dbg <= grid_stop;
      ckdiff_stop_dbg <= ckdiff_stop;
      np_n_dbg <= np_n_mux;
      np_j_dbg <= np_j_mux;
      np_midx_dbg <= np_midx_mux;
    end
  end

endmodule
