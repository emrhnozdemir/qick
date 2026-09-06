`timescale 1ns / 1ps

module adaptive_sweep (
  input clk,
  input rst_n,

  input qtag_en_i,
  input [4:0] qtag_op_i,
  input [31:0] qtag_dt1_i,
  input [31:0] qtag_dt2_i,
  input [31:0] qtag_dt3_i,
  input [31:0] qtag_dt4_i,
  (* MARK_DEBUG = "TRUE" *) output reg qtag_rdy_o,
  (* MARK_DEBUG = "TRUE" *) output reg [31:0] qtag_dt1_o,
  (* MARK_DEBUG = "TRUE" *) output reg [31:0] qtag_dt2_o,
  (* MARK_DEBUG = "TRUE" *) output reg qtag_vld_o,

  (* MARK_DEBUG = "TRUE" *) output interrupt_o,

  input s_axis_tvalid,
  output s_axis_tready,
  input [63:0] s_axis_tdata,

  input s_axi_aclk,
  input s_axi_aresetn,
  input [7:0] s_axi_awaddr,
  input [2:0] s_axi_awprot,
  input s_axi_awvalid,
  output s_axi_awready,
  input [31:0] s_axi_wdata,
  input [3:0] s_axi_wstrb,
  input s_axi_wvalid,
  output s_axi_wready,
  output [1:0] s_axi_bresp,
  output s_axi_bvalid,
  input s_axi_bready,
  input [7:0] s_axi_araddr,
  input [2:0] s_axi_arprot,
  input s_axi_arvalid,
  output s_axi_arready,
  output [31:0] s_axi_rdata,
  output [1:0] s_axi_rresp,
  output s_axi_rvalid,
  input s_axi_rready
);

  assign s_axis_tready = 1'b1;

  (* MARK_DEBUG = "TRUE" *) reg en_d;
  wire en_rise = qtag_en_i & ~en_d;

  always @(posedge clk) begin
    if (!rst_n)
      en_d <= 1'b0;
    else
      en_d <= qtag_en_i;
  end

  (* MARK_DEBUG = "TRUE" *) wire cfg_sweep = en_rise & (qtag_op_i == 5'd0);
  (* MARK_DEBUG = "TRUE" *) wire start_now = en_rise & (qtag_op_i == 5'd1);
  (* MARK_DEBUG = "TRUE" *) wire cfg_meas = en_rise & (qtag_op_i == 5'd2);
  (* MARK_DEBUG = "TRUE" *) wire status_rd = en_rise & (qtag_op_i == 5'd3);
  (* MARK_DEBUG = "TRUE" *) wire diag_rd = en_rise & (qtag_op_i == 5'd4);
  (* MARK_DEBUG = "TRUE" *) wire run_gdkw = en_rise & ((qtag_op_i == 5'd5) | (qtag_op_i == 5'd6));
  (* MARK_DEBUG = "TRUE" *) wire getfreq_rd = en_rise & (qtag_op_i == 5'd7);
  (* MARK_DEBUG = "TRUE" *) wire gdkw_diag_rd = en_rise & (qtag_op_i == 5'd8);
  (* MARK_DEBUG = "TRUE" *) wire cfg_gdkw = en_rise & (qtag_op_i == 5'd9);
  (* MARK_DEBUG = "TRUE" *) wire clr_result = en_rise & (qtag_op_i == 5'd10);
  (* MARK_DEBUG = "TRUE" *) wire getmean_rd = en_rise & (qtag_op_i == 5'd11);
  (* MARK_DEBUG = "TRUE" *) wire rearm_now = en_rise & (qtag_op_i == 5'd14);

  wire [15:0] threshold;
  wire [31:0] block_tol;
  wire step_lut_write;
  wire [5:0] step_lut_addr;
  wire [31:0] step_lut_data;
  wire [6:0] step_lut_len;
  wire offset_lut_write;
  wire [5:0] offset_lut_addr;
  wire [31:0] offset_lut_data;
  wire [6:0] offset_lut_len;

  wire [31:0] cfg_start;
  wire [31:0] cfg_step;
  wire [15:0] cfg_npoints;
  wire [4:0] cfg_avg_shift;
  wire [31:0] cfg_warmup_shots;
  wire [31:0] cfg_nmin;
  wire [31:0] cfg_flo;
  wire [31:0] cfg_fhi;
  wire [15:0] cfg_pair_min;
  wire [15:0] cfg_pair_max;

  wire search_mode;
  wire estop_hold;
  wire estop_en;
  wire block_en;
  wire [2:0] cfg_confirm;

  register_bank registers(
    .clk(clk),
    .rst_n(rst_n),
    .s_axi_aclk(s_axi_aclk),
    .s_axi_aresetn(s_axi_aresetn),
    .s_axi_awaddr(s_axi_awaddr),
    .s_axi_awprot(s_axi_awprot),
    .s_axi_awvalid(s_axi_awvalid),
    .s_axi_awready(s_axi_awready),
    .s_axi_wdata(s_axi_wdata),
    .s_axi_wstrb(s_axi_wstrb),
    .s_axi_wvalid(s_axi_wvalid),
    .s_axi_wready(s_axi_wready),
    .s_axi_bresp(s_axi_bresp),
    .s_axi_bvalid(s_axi_bvalid),
    .s_axi_bready(s_axi_bready),
    .s_axi_araddr(s_axi_araddr),
    .s_axi_arprot(s_axi_arprot),
    .s_axi_arvalid(s_axi_arvalid),
    .s_axi_arready(s_axi_arready),
    .s_axi_rdata(s_axi_rdata),
    .s_axi_rresp(s_axi_rresp),
    .s_axi_rvalid(s_axi_rvalid),
    .s_axi_rready(s_axi_rready),
    .cfg_sweep_i(cfg_sweep),
    .cfg_meas_i(cfg_meas),
    .cfg_search_i(cfg_gdkw),
    .dt1_i(qtag_dt1_i),
    .dt2_i(qtag_dt2_i),
    .dt3_i(qtag_dt3_i),
    .dt4_i(qtag_dt4_i),
    .start_freq_o(cfg_start),
    .step_o(cfg_step),
    .n_points_o(cfg_npoints),
    .avg_shift_o(cfg_avg_shift),
    .warmup_shots_o(cfg_warmup_shots),
    .n_min_o(cfg_nmin),
    .f_lo_o(cfg_flo),
    .f_hi_o(cfg_fhi),
    .pair_min_o(cfg_pair_min),
    .pair_max_o(cfg_pair_max),
    .threshold_o(threshold),
    .block_tol_o(block_tol),
    .search_mode_o(search_mode),
    .estop_hold_o(estop_hold),
    .estop_en_o(estop_en),
    .block_en_o(block_en),
    .confirm_o(cfg_confirm),
    .step_lut_write_o(step_lut_write),
    .step_lut_addr_o(step_lut_addr),
    .step_lut_data_o(step_lut_data),
    .step_lut_len_o(step_lut_len),
    .offset_lut_write_o(offset_lut_write),
    .offset_lut_addr_o(offset_lut_addr),
    .offset_lut_data_o(offset_lut_data),
    .offset_lut_len_o(offset_lut_len)
  );

  wire [31:0] status_word;

  wire pf_freq_valid;
  wire pf_finish;
  wire [31:0] best_freq;
  wire [31:0] pf_best_mean_i;
  wire [31:0] pf_best_mean_q;
  wire [15:0] pf_point_idx;

  wire ac_warmup_done;
  wire ac_early_stop;
  wire [31:0] ac_n_used;
  wire [31:0] ac_mean_i;
  wire [31:0] ac_mean_q;
  wire ac_log_wr;
  wire [15:0] ac_log_entry;
  wire [63:0] ac_power;
  wire ac_power_valid;
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

  (* MARK_DEBUG = "TRUE" *) reg busy;
  (* MARK_DEBUG = "TRUE" *) reg finish_seen;

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
    end
  end

  (* MARK_DEBUG = "TRUE" *) reg dest_r;

  always @(posedge clk) begin
    if (!rst_n)
      dest_r <= 1'b0;
    else if (start_now)
      dest_r <= 1'b0;
    else if (run_gdkw)
      dest_r <= 1'b1;
  end

  assign status_word = {pf_point_idx,
                        eng_freq_valid,
                        eng_busy,
                        eng_converged,
                        eng_capped,
                        dest_r,
                        estop_en,
                        1'b0,
                        ac_early_stop,
                        ac_warmup_done,
                        3'd0,
                        search_mode,
                        busy,
                        finish_seen,
                        1'b0};

  (* MARK_DEBUG = "TRUE" *) reg res_pend;

  always @(posedge clk) begin
    if (!rst_n)
      res_pend <= 1'b0;
    else if (start_now | run_gdkw | clr_result)
      res_pend <= 1'b0;
    else if (pf_finish | eng_done)
      res_pend <= 1'b1;
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
      qtag_dt1_o <= best_freq;
      qtag_dt2_o <= 32'd0;
      qtag_vld_o <= 1'b1;
    end else if (eng_done) begin
      qtag_dt1_o <= eng_x;
      qtag_dt2_o <= {eng_iter, 14'd0, eng_capped, eng_converged};
      qtag_vld_o <= 1'b1;
    end else if (clr_result) begin
      qtag_vld_o <= 1'b0;
    end else if (status_rd & ~res_pend) begin
      qtag_dt1_o <= status_word;
      qtag_dt2_o <= best_freq;
      qtag_vld_o <= 1'b1;
    end else if (diag_rd & ~res_pend) begin
      qtag_dt1_o <= ac_n_used;
      qtag_dt2_o <= {nconv_cnt, 5'd0, ac_log_entry[10:0]};
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
    end
  end

  always @(posedge clk) begin
    if (!rst_n)
      qtag_rdy_o <= 1'b1;
    else if (start_now | run_gdkw)
      qtag_rdy_o <= 1'b0;
    else if (pf_finish | eng_done)
      qtag_rdy_o <= 1'b1;
  end

  (* MARK_DEBUG = "TRUE" *) reg int_en;
  (* MARK_DEBUG = "TRUE" *) reg int_pulse;
  (* MARK_DEBUG = "TRUE" *) reg draining;
  (* MARK_DEBUG = "TRUE" *) reg arm_pend;
  (* MARK_DEBUG = "TRUE" *) reg [31:0] drain_drop_cnt;

  wire ac_early_pulse;
  wire drain_set = ac_early_pulse & int_en;
  wire drain_now = draining & ~rearm_now;
  wire arm_req = pf_freq_valid | eng_probe_arm;

  assign interrupt_o = int_pulse;

  always @(posedge clk) begin
    if (!rst_n) begin
      int_pulse <= 1'b0;
    end else begin
      int_pulse <= drain_set;
    end
  end

  always @(posedge clk) begin
    if (!rst_n) begin
      int_en <= 1'b0;
    end else if (cfg_meas) begin
      int_en <= 1'b0;
    end else if (rearm_now) begin
      int_en <= 1'b1;
    end
  end

  always @(posedge clk) begin
    if (!rst_n) begin
      draining <= 1'b0;
    end else if (start_now | run_gdkw) begin
      draining <= 1'b0;
    end else if (drain_set) begin
      draining <= 1'b1;
    end else if (rearm_now) begin
      draining <= 1'b0;
    end
  end

  always @(posedge clk) begin
    if (!rst_n) begin
      arm_pend <= 1'b0;
    end else if (start_now | run_gdkw) begin
      arm_pend <= 1'b0;
    end else if (rearm_now) begin
      arm_pend <= 1'b0;
    end else if (arm_req & drain_now) begin
      arm_pend <= 1'b1;
    end
  end

  always @(posedge clk) begin
    if (!rst_n) begin
      drain_drop_cnt <= 32'd0;
    end else if (start_now | run_gdkw) begin
      drain_drop_cnt <= 32'd0;
    end else if (drain_now & s_axis_tvalid) begin
      drain_drop_cnt <= drain_drop_cnt + 32'd1;
    end
  end

  wire point_arm = start_now | (arm_req & ~drain_now) | (rearm_now & arm_pend);

  amplitude_calculator u_amplitude_calculator (
    .clk               (clk),
    .rst_n             (rst_n),
    .s_axis_tvalid     (s_axis_tvalid),
    .s_axis_tready     (s_axis_tready),
    .s_axis_tdata      (s_axis_tdata),
    .arm_i             (point_arm),
    .avg_shift_i       (cfg_avg_shift),
    .warmup_shots_i              (cfg_warmup_shots),
    .n_min_i           (cfg_nmin),
    .estop_en_i        (estop_en),
    .estop_hold_i      (estop_hold),
    .threshold_i       (threshold),
    .block_en_i        (block_en),
    .block_tol_i       (block_tol),
    .confirm_i         (cfg_confirm),
    .warmup_done_o     (ac_warmup_done),
    .early_stop_o      (ac_early_stop),
    .early_pulse_o     (ac_early_pulse),
    .n_used_o          (ac_n_used),
    .mean_i_o          (ac_mean_i),
    .mean_q_o          (ac_mean_q),
    .log_wr_o          (ac_log_wr),
    .log_entry_o       (ac_log_entry),
    .power_o           (ac_power),
    .power_valid_o     (ac_power_valid)
  );

  always @(posedge clk) begin
    if (!rst_n)
      nconv_cnt <= 16'd0;
    else if (start_now | run_gdkw)
      nconv_cnt <= 16'd0;
    else if (ac_log_wr & ~ac_log_entry[8])
      nconv_cnt <= nconv_cnt + 16'd1;
  end

  (* MARK_DEBUG = "TRUE" *) wire grid_valid = ac_power_valid & ~dest_r;
  (* MARK_DEBUG = "TRUE" *) wire search_valid = ac_power_valid & dest_r;

  gradient_engine u_gradient_engine (
    .clk               (clk),
    .rst_n             (rst_n),
    .start_i           (run_gdkw),
    .two_sided_i       (qtag_op_i == 5'd6),
    .scheduled_i       (qtag_dt2_i[0]),
    .dip_i             (search_mode),
    .x0_i              (qtag_dt1_i),
    .f_lo_i            (cfg_flo),
    .f_hi_i            (cfg_fhi),
    .step_i            (cfg_step),
    .min_step_i        (qtag_dt3_i),
    .max_iteration_i   (qtag_dt4_i[15:0]),
    .patience_i        (qtag_dt2_i[23:16]),
    .lambda_i          (qtag_dt2_i[8:4]),
    .pair_min_i        (cfg_pair_min),
    .pair_max_i        (cfg_pair_max),
    .step_lut_write_i  (step_lut_write),
    .step_lut_addr_i   (step_lut_addr),
    .step_lut_data_i   (step_lut_data),
    .step_lut_len_i    (step_lut_len),
    .offset_lut_write_i(offset_lut_write),
    .offset_lut_addr_i (offset_lut_addr),
    .offset_lut_data_i (offset_lut_data),
    .offset_lut_len_i  (offset_lut_len),
    .freq_word_o       (eng_freq_word),
    .freq_valid_o      (eng_freq_valid),
    .freq_ack_i        (eng_freq_ack),
    .probe_arm_o       (eng_probe_arm),
    .amp_valid_i       (search_valid),
    .amp_data_i        (ac_power),
    .busy_o            (eng_busy),
    .done_o            (eng_done),
    .converged_o       (eng_converged),
    .capped_o          (eng_capped),
    .x_o               (eng_x),
    .iteration_o       (eng_iter),
    .pairs_o           (eng_pairs),
    .signed_sum_high_o (eng_sd_hi)
  );

  peak_finder u_peak_finder (
    .clk            (clk),
    .rst_n          (rst_n),
    .start_i        (start_now),
    .start_freq_i   (cfg_start),
    .step_i         (cfg_step),
    .n_points_i     (cfg_npoints),
    .dip_i          (search_mode),
    .amp_valid_i    (grid_valid),
    .amp_data_i     (ac_power),
    .mean_i_i       (ac_mean_i),
    .mean_q_i       (ac_mean_q),
    .freq_valid_o   (pf_freq_valid),
    .finish_o       (pf_finish),
    .best_freq_o    (best_freq),
    .best_mean_i_o  (pf_best_mean_i),
    .best_mean_q_o  (pf_best_mean_q),
    .point_idx_o    (pf_point_idx)
  );

endmodule
