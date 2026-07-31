`timescale 1ns / 1ps

module amp_calc (
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

  input wire thr_wr_en_i,
  input wire [4:0] thr_wr_addr_i,
  input wire [45:0] thr_wr_data_i,

  output wire warmup_done_o,
  output wire early_stop_o,
  output wire [31:0] n_used_o,
  output wire [45:0] dev_acc_o,

  output wire [127:0] power_o,
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

  always @(posedge clk) begin
    if (!rst_n) begin
      s1_r <= 5'd0;
      s2_r <= 5'd0;
      red_sel_r <= 3'd0;
    end else if (arm_i) begin
      s1_r <= prescale_en_i ? s1_w : 5'd0;
      s2_r <= s2_w;
      red_sel_r <= reduce_sel_i;
    end else begin
      s1_r <= s1_r;
      s2_r <= s2_r;
      red_sel_r <= red_sel_r;
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
  wire acc_clr;
  wire acc_en;
  wire is_last;
  wire stop_now;
  wire point_latch;
  wire emit;
  wire es_stop;

  shot_sequencer u_shot_sequencer (
    .clk               (clk),
    .rst_n             (rst_n),
    .arm_i             (arm_i),
    .shot_i            (shot_v_r),
    .averager_value_i  (averager_value_i),
    .n0_i              (n0_i),
    .stop_i            (es_stop),
    .stop_hold_i       (estop_hold_i),
    .armed_o           (),
    .stopped_o         (),
    .first_o           (seq_first),
    .n_o               (seq_n),
    .acc_clr_o         (acc_clr),
    .acc_en_o          (acc_en),
    .is_last_o         (is_last),
    .stop_now_o        (stop_now),
    .point_latch_o     (point_latch),
    .emit_o            (emit),
    .warmup_done_o     (warmup_done_o),
    .early_o           (early_stop_o),
    .n_used_o          (n_used_o)
  );

  wire signed [63:0] acc_i_d = {{31{xs_i_r[32]}}, xs_i_r};
  wire signed [63:0] acc_q_d = {{31{xs_q_r[32]}}, xs_q_r};

  wire signed [63:0] acc_i_nxt;
  wire signed [63:0] acc_q_nxt;

  signed_accumulator #(.W(64)) u_acc_i (
    .clk     (clk),
    .rst_n   (rst_n),
    .clr     (acc_clr),
    .en      (acc_en),
    .d_i     (acc_i_d),
    .q_o     (),
    .q_nxt_o (acc_i_nxt)
  );

  signed_accumulator #(.W(64)) u_acc_q (
    .clk     (clk),
    .rst_n   (rst_n),
    .clr     (acc_clr),
    .en      (acc_en),
    .d_i     (acc_q_d),
    .q_o     (),
    .q_nxt_o (acc_q_nxt)
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
    .mean_o     (),
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
    .mean_o     (),
    .mean_nxt_o (mean_q_nxt)
  );

  wire [4:0] es_j;
  wire [4:0] shift_amt = is_last ? s2_r : es_j;

  wire signed [64:0] acc_i_nxt65 = {acc_i_nxt[63], acc_i_nxt};
  wire signed [64:0] acc_q_nxt65 = {acc_q_nxt[63], acc_q_nxt};

  wire signed [64:0] red_i;
  wire signed [64:0] red_q;

  round_shift #(.W(65)) u_reduce_i (
    .d_i  (acc_i_nxt65),
    .sh_i (shift_amt),
    .y_o  (red_i)
  );

  round_shift #(.W(65)) u_reduce_q (
    .d_i  (acc_q_nxt65),
    .sh_i (shift_amt),
    .y_o  (red_q)
  );

  early_stop_mad u_early_stop_mad (
    .clk           (clk),
    .rst_n         (rst_n),
    .arm_i         (arm_i),
    .en_i          (estop_en_i),
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

  wire signed [63:0] pt_i_shift = {{46{red_i[17]}}, red_i[17:0]};
  wire signed [63:0] pt_q_shift = {{46{red_q[17]}}, red_q[17:0]};
  wire signed [63:0] pt_i_mean = {{46{mean_i_nxt[17]}}, mean_i_nxt};
  wire signed [63:0] pt_q_mean = {{46{mean_q_nxt[17]}}, mean_q_nxt};

  wire signed [63:0] pt_i_new = (red_sel_r == 3'd0) ? acc_i_nxt :
                                (red_sel_r == 3'd1) ? pt_i_shift :
                                (red_sel_r == 3'd2) ? pt_i_mean : {64{1'b0}};
  wire signed [63:0] pt_q_new = (red_sel_r == 3'd0) ? acc_q_nxt :
                                (red_sel_r == 3'd1) ? pt_q_shift :
                                (red_sel_r == 3'd2) ? pt_q_mean : {64{1'b0}};

  (* mark_debug = "true" *) reg signed [63:0] point_i;
  (* mark_debug = "true" *) reg signed [63:0] point_q;

  always @(posedge clk) begin
    if (!rst_n) begin
      point_i <= {64{1'b0}};
      point_q <= {64{1'b0}};
    end else if (point_latch) begin
      point_i <= pt_i_new;
      point_q <= pt_q_new;
    end else begin
      point_i <= point_i;
      point_q <= point_q;
    end
  end

  power_macc u_power_macc (
    .clk     (clk),
    .rst_n   (rst_n),
    .start_i (emit),
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
    end
  end

endmodule
