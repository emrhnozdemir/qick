`timescale 1ns / 1ps

module adaptive_sweep (
  input wire clk,
  input wire rst_n,

  input wire qtag_en_i,
  input wire [4:0] qtag_op_i,
  input wire [31:0] qtag_dt1_i,
  input wire [31:0] qtag_dt2_i,
  input wire [31:0] qtag_dt3_i,
  input wire [31:0] qtag_dt4_i,
  (* mark_debug = "true" *) output reg qtag_rdy_o,
  (* mark_debug = "true" *) output reg [31:0] qtag_dt1_o,
  (* mark_debug = "true" *) output reg [31:0] qtag_dt2_o,
  (* mark_debug = "true" *) output reg qtag_vld_o,

  input wire s_axis_tvalid,
  output wire s_axis_tready,
  input wire [63:0] s_axis_tdata,

  input wire s_axi_aclk,
  input wire s_axi_aresetn,
  input wire [7:0] s_axi_awaddr,
  input wire [2:0] s_axi_awprot,
  input wire s_axi_awvalid,
  output wire s_axi_awready,
  input wire [31:0] s_axi_wdata,
  input wire [3:0] s_axi_wstrb,
  input wire s_axi_wvalid,
  output wire s_axi_wready,
  output wire [1:0] s_axi_bresp,
  output wire s_axi_bvalid,
  input wire s_axi_bready,
  input wire [7:0] s_axi_araddr,
  input wire [2:0] s_axi_arprot,
  input wire s_axi_arvalid,
  output wire s_axi_arready,
  output wire [31:0] s_axi_rdata,
  output wire [1:0] s_axi_rresp,
  output wire s_axi_rvalid,
  input wire s_axi_rready
);

  assign s_axis_tready = 1'b1;

  (* mark_debug = "true" *) reg en_d;
  wire en_rise = qtag_en_i & ~en_d;

  always @(posedge clk) begin
    if (!rst_n)
      en_d <= 1'b0;
    else
      en_d <= qtag_en_i;
  end

  wire cfg_sweep = en_rise & (qtag_op_i == 5'd0);
  wire start_now = en_rise & (qtag_op_i == 5'd1);
  wire cfg_meas = en_rise & (qtag_op_i == 5'd2);
  wire status_rd = en_rise & (qtag_op_i == 5'd3);
  wire op_thr_wr = en_rise & (qtag_op_i == 5'd4);
  wire diag_rd = en_rise & (qtag_op_i == 5'd5);
  wire run_gdkw = en_rise & ((qtag_op_i == 5'd6) | (qtag_op_i == 5'd7));
  wire op_alut_wr = en_rise & (qtag_op_i == 5'd8);
  wire op_clut_wr = en_rise & (qtag_op_i == 5'd9);
  wire getfreq_rd = en_rise & (qtag_op_i == 5'd10);
  wire gdkw_diag_rd = en_rise & (qtag_op_i == 5'd11);
  wire cfg_gdkw = en_rise & (qtag_op_i == 5'd12);
  wire clr_result = en_rise & (qtag_op_i == 5'd13);
  wire getmean_rd = en_rise & (qtag_op_i == 5'd14);
  wire getlog_rd = en_rise & (qtag_op_i == 5'd15);
  wire cfg_capdiv = en_rise & (qtag_op_i == 5'd16);

  reg [53:0] cap_mag_r;
  reg [5:0] cap_kp1_r;
  reg [4:0] cap_sft_r;

  always @(posedge clk) begin
    if (!rst_n) begin
      cap_mag_r <= 54'd4503599627370496;
      cap_kp1_r <= 6'd1;
      cap_sft_r <= 5'd0;
    end else if (cfg_capdiv) begin
      cap_mag_r <= {qtag_dt2_i[21:0], qtag_dt1_i};
      cap_kp1_r <= qtag_dt2_i[27:22];
      cap_sft_r <= qtag_dt3_i[4:0];
    end else begin
      cap_mag_r <= cap_mag_r;
      cap_kp1_r <= cap_kp1_r;
      cap_sft_r <= cap_sft_r;
    end
  end

  wire [31:0] REG0_REG;
  wire [31:0] REG1_REG;
  wire [31:0] REG2_REG;
  wire [31:0] REG3_REG;
  wire [31:0] REG4_REG;
  wire [31:0] REG5_REG;
  wire [31:0] REG6_REG;
  wire [31:0] REG7_REG;

  axi_slv_adaptive_sweep u_axi_slv (
    .s_axi_aclk    (s_axi_aclk),
    .s_axi_aresetn (s_axi_aresetn),
    .s_axi_awaddr  (s_axi_awaddr),
    .s_axi_awprot  (s_axi_awprot),
    .s_axi_awvalid (s_axi_awvalid),
    .s_axi_awready (s_axi_awready),
    .s_axi_wdata   (s_axi_wdata),
    .s_axi_wstrb   (s_axi_wstrb),
    .s_axi_wvalid  (s_axi_wvalid),
    .s_axi_wready  (s_axi_wready),
    .s_axi_bresp   (s_axi_bresp),
    .s_axi_bvalid  (s_axi_bvalid),
    .s_axi_bready  (s_axi_bready),
    .s_axi_araddr  (s_axi_araddr),
    .s_axi_arprot  (s_axi_arprot),
    .s_axi_arvalid (s_axi_arvalid),
    .s_axi_arready (s_axi_arready),
    .s_axi_rdata   (s_axi_rdata),
    .s_axi_rresp   (s_axi_rresp),
    .s_axi_rvalid  (s_axi_rvalid),
    .s_axi_rready  (s_axi_rready),
    .REG0_REG      (REG0_REG),
    .REG1_REG      (REG1_REG),
    .REG2_REG      (REG2_REG),
    .REG3_REG      (REG3_REG),
    .REG4_REG      (REG4_REG),
    .REG5_REG      (REG5_REG),
    .REG6_REG      (REG6_REG),
    .REG7_REG      (REG7_REG)
  );

  (* mark_debug = "true" *) reg axi_tgl_s0, axi_tgl_s1, axi_tgl_s2;

  always @(posedge clk) begin
    if (!rst_n) begin
      axi_tgl_s0 <= 1'b0;
      axi_tgl_s1 <= 1'b0;
      axi_tgl_s2 <= 1'b0;
    end else begin
      axi_tgl_s0 <= REG0_REG[31];
      axi_tgl_s1 <= axi_tgl_s0;
      axi_tgl_s2 <= axi_tgl_s1;
    end
  end

  wire axi_tbl_wr = axi_tgl_s1 ^ axi_tgl_s2;
  wire axi_alut_wr = axi_tbl_wr & (REG0_REG[9:8] == 2'd0);
  wire axi_clut_wr = axi_tbl_wr & (REG0_REG[9:8] == 2'd1);
  wire axi_thr_wr = axi_tbl_wr & (REG0_REG[9:8] == 2'd2);
  wire axi_ctrl_wr = axi_tbl_wr & (REG0_REG[9:8] == 2'd3);

  wire alut_wr_en = op_alut_wr | axi_alut_wr;
  wire [5:0] alut_wr_addr = op_alut_wr ? qtag_dt1_i[5:0] : REG0_REG[5:0];
  wire [31:0] alut_wr_data = op_alut_wr ? qtag_dt2_i : REG1_REG;

  wire clut_wr_en = op_clut_wr | axi_clut_wr;
  wire [5:0] clut_wr_addr = op_clut_wr ? qtag_dt1_i[5:0] : REG0_REG[5:0];
  wire [31:0] clut_wr_data = op_clut_wr ? qtag_dt2_i : REG1_REG;

  wire thr_wr_en = op_thr_wr | axi_thr_wr;
  wire [4:0] thr_wr_addr = op_thr_wr ? qtag_dt1_i[4:0] : REG0_REG[4:0];
  wire [45:0] thr_wr_data = op_thr_wr ? {qtag_dt3_i[13:0], qtag_dt2_i} : {REG2_REG[13:0], REG1_REG};

  (* mark_debug = "true" *) reg [6:0] reg_alut_len, reg_clut_len;

  always @(posedge clk) begin
    if (!rst_n) begin
      reg_alut_len <= 7'd64;
      reg_clut_len <= 7'd64;
    end else begin
      if (op_alut_wr & (qtag_dt3_i[6:0] != 7'd0))
        reg_alut_len <= qtag_dt3_i[6:0];
      else if (axi_alut_wr & (REG3_REG[6:0] != 7'd0))
        reg_alut_len <= REG3_REG[6:0];
      else
        reg_alut_len <= reg_alut_len;

      if (op_clut_wr & (qtag_dt3_i[6:0] != 7'd0))
        reg_clut_len <= qtag_dt3_i[6:0];
      else if (axi_clut_wr & (REG3_REG[6:0] != 7'd0))
        reg_clut_len <= REG3_REG[6:0];
      else
        reg_clut_len <= reg_clut_len;
    end
  end

  wire [31:0] cfg_start;
  wire [31:0] cfg_step;
  wire [31:0] cfg_npoints;
  wire [31:0] cfg_avg;
  wire [31:0] cfg_nsamp;
  wire [31:0] cfg_n0;
  wire [31:0] cfg_nmin;
  wire [31:0] cfg_flo;
  wire [31:0] cfg_fhi;
  wire [15:0] cfg_mmin;
  wire [15:0] cfg_mmax;

  wire search_mode;
  wire [2:0] reduce_sel;
  wire estop_hold;
  wire prescale_en;
  wire estop_en;
  wire [1:0] cfg_estop_sel;
  wire [3:0] cfg_m;
  wire cfg_ckmon;
  wire [1:0] cfg_density;
  wire [2:0] cfg_confirm;
  wire [31:0] status_word;

  wire [31:0] pf_freq_word;
  wire pf_freq_valid;
  wire pf_finish;
  wire [127:0] max_amplitude;
  wire [31:0] freq_at_max;
  wire [31:0] pf_best_mean_i;
  wire [31:0] pf_best_mean_q;
  wire [31:0] pf_point_idx;

  wire ac_warmup_done;
  wire ac_early_stop;
  wire [31:0] ac_n_used;
  wire [45:0] ac_dev_acc;
  wire [31:0] ac_mean_i;
  wire [31:0] ac_mean_q;
  wire ac_log_wr;
  wire [15:0] ac_log_entry;
  wire ac_drift;
  wire [127:0] ac_power;
  wire ac_power_valid;
  wire [15:0] log_cnt;
  wire [15:0] log_rd_data;
  wire log_rd_valid;
  reg getlog_d1;
  reg [15:0] nconv_cnt;

  wire [31:0] eng_freq_word;
  wire eng_freq_valid;
  wire eng_probe_arm;
  wire eng_busy;
  wire eng_done;
  wire eng_converged;
  wire eng_capped;
  wire [31:0] eng_x;
  wire [15:0] eng_iter;
  wire [15:0] eng_pairs;
  wire [31:0] eng_sd_hi;

  wire eng_freq_ack = getfreq_rd & eng_freq_valid;

  (* mark_debug = "true" *) reg busy;
  (* mark_debug = "true" *) reg finish_seen;

  always @(posedge clk) begin
    if (!rst_n) begin
      busy <= 1'b0;
      finish_seen <= 1'b0;
    end else if (start_now) begin
      busy <= 1'b1;
      finish_seen <= 1'b0;
    end else if (pf_finish) begin
      busy <= 1'b0;
      finish_seen <= 1'b1;
    end else begin
      busy <= busy;
      finish_seen <= finish_seen;
    end
  end

  (* mark_debug = "true" *) reg dest_r;

  always @(posedge clk) begin
    if (!rst_n)
      dest_r <= 1'b0;
    else if (start_now)
      dest_r <= 1'b0;
    else if (run_gdkw)
      dest_r <= 1'b1;
    else
      dest_r <= dest_r;
  end

  ctrl_status_reg u_ctrl_status_reg (
    .clk              (clk),
    .rst_n            (rst_n),
    .cfg_sweep_i      (cfg_sweep),
    .cfg_meas_i       (cfg_meas),
    .cfg_search_i     (cfg_gdkw),
    .dt1_i            (qtag_dt1_i),
    .dt2_i            (qtag_dt2_i),
    .dt3_i            (qtag_dt3_i),
    .dt4_i            (qtag_dt4_i),
    .ctrl_wr_i        (axi_ctrl_wr),
    .ctrl_wr_data_i   (REG1_REG),
    .start_freq_o     (cfg_start),
    .step_o           (cfg_step),
    .n_points_o       (cfg_npoints),
    .averager_o       (cfg_avg),
    .nsamp_o          (cfg_nsamp),
    .n0_o             (cfg_n0),
    .n_min_o          (cfg_nmin),
    .f_lo_o           (cfg_flo),
    .f_hi_o           (cfg_fhi),
    .m_min_o          (cfg_mmin),
    .m_max_o          (cfg_mmax),
    .ctrl_o           (),
    .search_mode_o    (search_mode),
    .reduce_sel_o     (reduce_sel),
    .estop_hold_o     (estop_hold),
    .prescale_en_o    (prescale_en),
    .estop_en_o       (estop_en),
    .estop_sel_o      (cfg_estop_sel),
    .m_o              (cfg_m),
    .ckmon_o          (cfg_ckmon),
    .density_o        (cfg_density),
    .confirm_o        (cfg_confirm),
    .drift_i          (ac_drift),
    .point_idx_i      (pf_point_idx[15:0]),
    .busy_i           (busy),
    .finish_seen_i    (finish_seen),
    .warmup_done_i    (ac_warmup_done),
    .early_stop_i     (ac_early_stop),
    .dest_i           (dest_r),
    .eng_freq_valid_i (eng_freq_valid),
    .eng_busy_i       (eng_busy),
    .eng_converged_i  (eng_converged),
    .eng_capped_i     (eng_capped),
    .status_o         (status_word)
  );

  (* mark_debug = "true" *) reg res_pend;

  always @(posedge clk) begin
    if (!rst_n)
      res_pend <= 1'b0;
    else if (start_now | run_gdkw | clr_result)
      res_pend <= 1'b0;
    else if (pf_finish | eng_done)
      res_pend <= 1'b1;
    else
      res_pend <= res_pend;
  end

  always @(posedge clk) begin
    if (!rst_n) begin
      qtag_dt1_o <= 32'd0;
      qtag_dt2_o <= 32'd0;
      qtag_vld_o <= 1'b0;
    end else if (start_now) begin
      qtag_dt1_o <= 32'd0;
      qtag_dt2_o <= 32'd0;
      qtag_vld_o <= 1'b0;
    end else if (pf_finish) begin
      qtag_dt1_o <= pf_freq_word;
      qtag_dt2_o <= 32'd0;
      qtag_vld_o <= 1'b1;
    end else if (eng_done) begin
      qtag_dt1_o <= eng_x;
      qtag_dt2_o <= {eng_iter, 14'd0, eng_capped, eng_converged};
      qtag_vld_o <= 1'b1;
    end else if (clr_result) begin
      qtag_dt1_o <= qtag_dt1_o;
      qtag_dt2_o <= qtag_dt2_o;
      qtag_vld_o <= 1'b0;
    end else if (status_rd & ~res_pend) begin
      qtag_dt1_o <= status_word;
      qtag_dt2_o <= freq_at_max;
      qtag_vld_o <= 1'b1;
    end else if (diag_rd & ~res_pend) begin
      qtag_dt1_o <= ac_n_used;
      qtag_dt2_o <= (cfg_estop_sel == 2'd0) ? ac_dev_acc[45:14] : {nconv_cnt, 5'd0, ac_log_entry[10:0]};
      qtag_vld_o <= 1'b1;
    end else if (getfreq_rd & ~res_pend) begin
      qtag_dt1_o <= eng_freq_word;
      qtag_dt2_o <= {31'd0, eng_freq_valid};
      qtag_vld_o <= 1'b1;
    end else if (gdkw_diag_rd & ~res_pend) begin
      qtag_dt1_o <= {eng_pairs, eng_iter};
      qtag_dt2_o <= eng_sd_hi;
      qtag_vld_o <= 1'b1;
    end else if (getmean_rd & ~res_pend) begin
      qtag_dt1_o <= dest_r ? ac_mean_i : pf_best_mean_i;
      qtag_dt2_o <= dest_r ? ac_mean_q : pf_best_mean_q;
      qtag_vld_o <= 1'b1;
    end else if (getlog_d1) begin
      qtag_dt1_o <= {log_rd_valid, 15'd0, log_rd_data};
      qtag_dt2_o <= {16'd0, log_cnt};
      qtag_vld_o <= 1'b1;
    end else begin
      qtag_dt1_o <= qtag_dt1_o;
      qtag_dt2_o <= qtag_dt2_o;
      qtag_vld_o <= qtag_vld_o;
    end
  end

  always @(posedge clk) begin
    if (!rst_n)
      qtag_rdy_o <= 1'b1;
    else if (start_now | run_gdkw)
      qtag_rdy_o <= 1'b0;
    else if (pf_finish | eng_done)
      qtag_rdy_o <= 1'b1;
    else
      qtag_rdy_o <= qtag_rdy_o;
  end

  wire point_arm = start_now | pf_freq_valid | eng_probe_arm;

  amp_calc u_amp_calc (
    .clk               (clk),
    .rst_n             (rst_n),
    .s_axis_tvalid     (s_axis_tvalid),
    .s_axis_tready     (s_axis_tready),
    .s_axis_tdata      (s_axis_tdata),
    .arm_i             (point_arm),
    .averager_value_i  (cfg_avg),
    .nsamp_i           (cfg_nsamp),
    .n0_i              (cfg_n0),
    .n_min_i           (cfg_nmin),
    .reduce_sel_i      (reduce_sel),
    .prescale_en_i     (prescale_en),
    .estop_en_i        (estop_en),
    .estop_hold_i      (estop_hold),
    .estop_sel_i       (cfg_estop_sel),
    .m_i               (cfg_m),
    .ckmon_i           (cfg_ckmon),
    .dens_i            (cfg_density),
    .confirm_i         (cfg_confirm),
    .cap_kp1_i         (cap_kp1_r),
    .cap_mag_i         (cap_mag_r),
    .cap_sft_i         (cap_sft_r),
    .thr_wr_en_i       (thr_wr_en),
    .thr_wr_addr_i     (thr_wr_addr),
    .thr_wr_data_i     (thr_wr_data),
    .warmup_done_o     (ac_warmup_done),
    .early_stop_o      (ac_early_stop),
    .n_used_o          (ac_n_used),
    .dev_acc_o         (ac_dev_acc),
    .mean_i_o          (ac_mean_i),
    .mean_q_o          (ac_mean_q),
    .log_wr_o          (ac_log_wr),
    .log_entry_o       (ac_log_entry),
    .drift_o           (ac_drift),
    .power_o           (ac_power),
    .power_valid_o     (ac_power_valid)
  );

  always @(posedge clk) begin
    if (!rst_n)
      getlog_d1 <= 1'b0;
    else
      getlog_d1 <= getlog_rd & ~res_pend;
  end

  always @(posedge clk) begin
    if (!rst_n)
      nconv_cnt <= 16'd0;
    else if (start_now | run_gdkw)
      nconv_cnt <= 16'd0;
    else if (ac_log_wr & ~ac_log_entry[8])
      nconv_cnt <= nconv_cnt + 16'd1;
    else
      nconv_cnt <= nconv_cnt;
  end

  stop_log u_stop_log (
    .clk        (clk),
    .rst_n      (rst_n),
    .clr_i      (start_now | run_gdkw),
    .wr_i       (ac_log_wr),
    .wr_entry_i (ac_log_entry),
    .rd_en_i    (getlog_rd),
    .rd_addr_i  (qtag_dt1_i[11:0]),
    .rd_data_o  (log_rd_data),
    .rd_valid_o (log_rd_valid),
    .cnt_o      (log_cnt)
  );

  wire [127:0] grid_data;
  wire grid_valid;
  wire [63:0] search_data;
  wire search_valid;

  result_router u_result_router (
    .power_i        (ac_power),
    .valid_i        (ac_power_valid),
    .dest_i         (dest_r),
    .grid_data_o    (grid_data),
    .grid_valid_o   (grid_valid),
    .search_data_o  (search_data),
    .search_valid_o (search_valid)
  );

  gd_kw_engine u_gd_kw_engine (
    .clk          (clk),
    .rst_n        (rst_n),
    .start        (run_gdkw),
    .kw_mode_i    (qtag_op_i[0]),
    .use_lut_i    (qtag_dt2_i[0]),
    .dip_i        (search_mode),
    .x0_i         (qtag_dt1_i),
    .f_lo_i       (cfg_flo),
    .f_hi_i       (cfg_fhi),
    .fstep_i      (cfg_step),
    .min_step_i   (qtag_dt3_i),
    .max_iter_i   (qtag_dt4_i[15:0]),
    .patience_i   (qtag_dt2_i[23:16]),
    .lambda_i     (qtag_dt2_i[8:4]),
    .m_min_i      (cfg_mmin),
    .m_max_i      (cfg_mmax),
    .alut_wr_en   (alut_wr_en),
    .alut_wr_addr (alut_wr_addr),
    .alut_wr_data (alut_wr_data),
    .alut_len_i   (reg_alut_len),
    .clut_wr_en   (clut_wr_en),
    .clut_wr_addr (clut_wr_addr),
    .clut_wr_data (clut_wr_data),
    .clut_len_i   (reg_clut_len),
    .freq_word_o  (eng_freq_word),
    .freq_valid_o (eng_freq_valid),
    .freq_ack_i   (eng_freq_ack),
    .probe_arm_o  (eng_probe_arm),
    .amp_valid_i  (search_valid),
    .amp_data_i   (search_data),
    .busy_o       (eng_busy),
    .done_o       (eng_done),
    .converged_o  (eng_converged),
    .capped_o     (eng_capped),
    .x_o          (eng_x),
    .iter_o       (eng_iter),
    .pairs_o      (eng_pairs),
    .sd_hi_o      (eng_sd_hi)
  );

  peak_finder_wide u_peak_finder_wide (
    .clk           (clk),
    .rstn          (rst_n),
    .start         (start_now),
    .start_freq    (cfg_start),
    .step          (cfg_step),
    .n_points      (cfg_npoints),
    .mode          (search_mode),
    .amp_valid     (grid_valid),
    .amp_data      (grid_data),
    .mean_i_i      (ac_mean_i),
    .mean_q_i      (ac_mean_q),
    .freq_word     (pf_freq_word),
    .freq_valid    (pf_freq_valid),
    .finish        (pf_finish),
    .max_amplitude (max_amplitude),
    .freq_at_max   (freq_at_max),
    .best_mean_i   (pf_best_mean_i),
    .best_mean_q   (pf_best_mean_q),
    .point_idx     (pf_point_idx)
  );

  (* mark_debug = "true" *) reg qtag_en_dbg;
  (* mark_debug = "true" *) reg [4:0] qtag_op_dbg;
  (* mark_debug = "true" *) reg [31:0] qtag_dt1_dbg;
  (* mark_debug = "true" *) reg [31:0] qtag_dt2_dbg;
  (* mark_debug = "true" *) reg [31:0] qtag_dt3_dbg;
  (* mark_debug = "true" *) reg [31:0] qtag_dt4_dbg;
  (* mark_debug = "true" *) reg en_rise_dbg;
  (* mark_debug = "true" *) reg s_axis_tvalid_dbg;
  (* mark_debug = "true" *) reg s_axis_tready_dbg;
  (* mark_debug = "true" *) reg [63:0] s_axis_tdata_dbg;
  (* mark_debug = "true" *) reg cfg_sweep_dbg;
  (* mark_debug = "true" *) reg start_now_dbg;
  (* mark_debug = "true" *) reg cfg_meas_dbg;
  (* mark_debug = "true" *) reg status_rd_dbg;
  (* mark_debug = "true" *) reg op_thr_wr_dbg;
  (* mark_debug = "true" *) reg diag_rd_dbg;
  (* mark_debug = "true" *) reg run_gdkw_dbg;
  (* mark_debug = "true" *) reg op_alut_wr_dbg;
  (* mark_debug = "true" *) reg op_clut_wr_dbg;
  (* mark_debug = "true" *) reg getfreq_rd_dbg;
  (* mark_debug = "true" *) reg gdkw_diag_rd_dbg;
  (* mark_debug = "true" *) reg cfg_gdkw_dbg;
  (* mark_debug = "true" *) reg clr_result_dbg;
  (* mark_debug = "true" *) reg axi_tbl_wr_dbg;
  (* mark_debug = "true" *) reg axi_alut_wr_dbg;
  (* mark_debug = "true" *) reg axi_clut_wr_dbg;
  (* mark_debug = "true" *) reg axi_thr_wr_dbg;
  (* mark_debug = "true" *) reg axi_ctrl_wr_dbg;
  (* mark_debug = "true" *) reg [31:0] reg0_dbg;
  (* mark_debug = "true" *) reg [31:0] reg1_dbg;
  (* mark_debug = "true" *) reg [31:0] reg2_dbg;
  (* mark_debug = "true" *) reg [31:0] reg3_dbg;
  (* mark_debug = "true" *) reg alut_wr_en_dbg;
  (* mark_debug = "true" *) reg [5:0] alut_wr_addr_dbg;
  (* mark_debug = "true" *) reg [31:0] alut_wr_data_dbg;
  (* mark_debug = "true" *) reg clut_wr_en_dbg;
  (* mark_debug = "true" *) reg [5:0] clut_wr_addr_dbg;
  (* mark_debug = "true" *) reg [31:0] clut_wr_data_dbg;
  (* mark_debug = "true" *) reg thr_wr_en_dbg;
  (* mark_debug = "true" *) reg [4:0] thr_wr_addr_dbg;
  (* mark_debug = "true" *) reg [45:0] thr_wr_data_dbg;
  (* mark_debug = "true" *) reg point_arm_dbg;
  (* mark_debug = "true" *) reg eng_freq_ack_dbg;
  (* mark_debug = "true" *) reg grid_valid_dbg;
  (* mark_debug = "true" *) reg search_valid_dbg;
  (* mark_debug = "true" *) reg [63:0] search_data_dbg;
  always @(posedge clk) begin
    if (!rst_n) begin
      qtag_en_dbg <= 1'b0;
      qtag_op_dbg <= 5'd0;
      qtag_dt1_dbg <= 32'd0;
      qtag_dt2_dbg <= 32'd0;
      qtag_dt3_dbg <= 32'd0;
      qtag_dt4_dbg <= 32'd0;
      en_rise_dbg <= 1'b0;
      s_axis_tvalid_dbg <= 1'b0;
      s_axis_tready_dbg <= 1'b0;
      s_axis_tdata_dbg <= 64'd0;
      cfg_sweep_dbg <= 1'b0;
      start_now_dbg <= 1'b0;
      cfg_meas_dbg <= 1'b0;
      status_rd_dbg <= 1'b0;
      op_thr_wr_dbg <= 1'b0;
      diag_rd_dbg <= 1'b0;
      run_gdkw_dbg <= 1'b0;
      op_alut_wr_dbg <= 1'b0;
      op_clut_wr_dbg <= 1'b0;
      getfreq_rd_dbg <= 1'b0;
      gdkw_diag_rd_dbg <= 1'b0;
      cfg_gdkw_dbg <= 1'b0;
      clr_result_dbg <= 1'b0;
      axi_tbl_wr_dbg <= 1'b0;
      axi_alut_wr_dbg <= 1'b0;
      axi_clut_wr_dbg <= 1'b0;
      axi_thr_wr_dbg <= 1'b0;
      axi_ctrl_wr_dbg <= 1'b0;
      reg0_dbg <= 32'd0;
      reg1_dbg <= 32'd0;
      reg2_dbg <= 32'd0;
      reg3_dbg <= 32'd0;
      alut_wr_en_dbg <= 1'b0;
      alut_wr_addr_dbg <= 6'd0;
      alut_wr_data_dbg <= 32'd0;
      clut_wr_en_dbg <= 1'b0;
      clut_wr_addr_dbg <= 6'd0;
      clut_wr_data_dbg <= 32'd0;
      thr_wr_en_dbg <= 1'b0;
      thr_wr_addr_dbg <= 5'd0;
      thr_wr_data_dbg <= {46{1'b0}};
      point_arm_dbg <= 1'b0;
      eng_freq_ack_dbg <= 1'b0;
      grid_valid_dbg <= 1'b0;
      search_valid_dbg <= 1'b0;
      search_data_dbg <= 64'd0;
    end else begin
      qtag_en_dbg <= qtag_en_i;
      qtag_op_dbg <= qtag_op_i;
      qtag_dt1_dbg <= qtag_dt1_i;
      qtag_dt2_dbg <= qtag_dt2_i;
      qtag_dt3_dbg <= qtag_dt3_i;
      qtag_dt4_dbg <= qtag_dt4_i;
      en_rise_dbg <= en_rise;
      s_axis_tvalid_dbg <= s_axis_tvalid;
      s_axis_tready_dbg <= s_axis_tready;
      s_axis_tdata_dbg <= s_axis_tdata;
      cfg_sweep_dbg <= cfg_sweep;
      start_now_dbg <= start_now;
      cfg_meas_dbg <= cfg_meas;
      status_rd_dbg <= status_rd;
      op_thr_wr_dbg <= op_thr_wr;
      diag_rd_dbg <= diag_rd;
      run_gdkw_dbg <= run_gdkw;
      op_alut_wr_dbg <= op_alut_wr;
      op_clut_wr_dbg <= op_clut_wr;
      getfreq_rd_dbg <= getfreq_rd;
      gdkw_diag_rd_dbg <= gdkw_diag_rd;
      cfg_gdkw_dbg <= cfg_gdkw;
      clr_result_dbg <= clr_result;
      axi_tbl_wr_dbg <= axi_tbl_wr;
      axi_alut_wr_dbg <= axi_alut_wr;
      axi_clut_wr_dbg <= axi_clut_wr;
      axi_thr_wr_dbg <= axi_thr_wr;
      axi_ctrl_wr_dbg <= axi_ctrl_wr;
      reg0_dbg <= REG0_REG;
      reg1_dbg <= REG1_REG;
      reg2_dbg <= REG2_REG;
      reg3_dbg <= REG3_REG;
      alut_wr_en_dbg <= alut_wr_en;
      alut_wr_addr_dbg <= alut_wr_addr;
      alut_wr_data_dbg <= alut_wr_data;
      clut_wr_en_dbg <= clut_wr_en;
      clut_wr_addr_dbg <= clut_wr_addr;
      clut_wr_data_dbg <= clut_wr_data;
      thr_wr_en_dbg <= thr_wr_en;
      thr_wr_addr_dbg <= thr_wr_addr;
      thr_wr_data_dbg <= thr_wr_data;
      point_arm_dbg <= point_arm;
      eng_freq_ack_dbg <= eng_freq_ack;
      grid_valid_dbg <= grid_valid;
      search_valid_dbg <= search_valid;
      search_data_dbg <= search_data;
    end
  end

endmodule
