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
  output reg qtag_rdy_o,
  output reg [31:0] qtag_dt1_o,
  output reg [31:0] qtag_dt2_o,
  output reg qtag_vld_o,

  output interrupt_o,

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
  input s_axi_rready,

  output [31:0] c_debug_do,
  output [31:0] c_data_do,
  output [31:0] ps_debug_do
);

  localparam [4:0] OP_CFG_WINDOW = 5'd0;
  localparam [4:0] OP_CFG_ACQ = 5'd1;
  localparam [4:0] OP_CFG_GDKW = 5'd2;
  localparam [4:0] OP_START = 5'd8;
  localparam [4:0] OP_RUN_KW = 5'd9;
  localparam [4:0] OP_CLR_RESULT = 5'd10;
  localparam [4:0] OP_REARM = 5'd11;
  localparam [4:0] OP_CFG_INTERRUPT = 5'd15;
  localparam [4:0] OP_GET_FREQ = 5'd16;
  localparam [4:0] OP_GET_STATUS = 5'd17;
  localparam [4:0] OP_GET_DIAG = 5'd18;
  localparam [4:0] OP_GET_MEAN = 5'd19;

  localparam [31:0] IDENT = 32'h4153_0500;

  assign s_axis_tready = 1'b1;

  reg en_d;
  wire en_rise = qtag_en_i & ~en_d;

  always @(posedge clk) begin
    if (!rst_n)
      en_d <= 1'b0;
    else
      en_d <= qtag_en_i;
  end

  wire cfg_sweep = en_rise & (qtag_op_i == OP_CFG_WINDOW);
  wire cfg_meas = en_rise & (qtag_op_i == OP_CFG_ACQ);
  wire cfg_gdkw = en_rise & (qtag_op_i == OP_CFG_GDKW);
  wire start_now = en_rise & (qtag_op_i == OP_START);
  wire run_kw = en_rise & (qtag_op_i == OP_RUN_KW);
  wire clr_result = en_rise & (qtag_op_i == OP_CLR_RESULT);
  wire rearm_now = en_rise & (qtag_op_i == OP_REARM);
  wire getfreq_rd = en_rise & (qtag_op_i == OP_GET_FREQ);
  wire status_rd = en_rise & (qtag_op_i == OP_GET_STATUS);
  wire diag_rd = en_rise & (qtag_op_i == OP_GET_DIAG);
  wire getmean_rd = en_rise & (qtag_op_i == OP_GET_MEAN);
  wire op_decoded = cfg_sweep | cfg_meas | cfg_gdkw | start_now | run_kw |
                    clr_result | rearm_now | getfreq_rd | status_rd | diag_rd |
                    getmean_rd;
  wire op_unknown = en_rise & ~op_decoded & (qtag_op_i != OP_CFG_INTERRUPT);

  wire [15:0] threshold;
  wire [31:0] block_tol;

  wire [31:0] cfg_start;
  wire [31:0] cfg_step;
  wire [15:0] cfg_npoints;
  wire [4:0] cfg_avg_shift;
  wire [31:0] cfg_warmup_shots;
  wire [31:0] cfg_nmin;
  wire [31:0] cfg_flo;
  wire [31:0] cfg_fhi;

  wire search_mode;
  wire estop_hold;
  wire estop_en;
  wire block_en;
  wire short_confirm;
  wire [2:0] cfg_confirm;
  wire [31:0] ctrl_word;

  wire [31:0] status_word;
  wire [31:0] dbg_dt1;
  wire [31:0] dbg_dt2;
  wire [3:0] read_sel;
  wire axi_commit;
  wire [4:0] axi_target;
  wire axi_bad_target;

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
    .status_i(status_word),
    .view_dt1_i(dbg_dt1),
    .view_dt2_i(dbg_dt2),
    .ident_i(IDENT),
    .start_freq_o(cfg_start),
    .step_o(cfg_step),
    .n_points_o(cfg_npoints),
    .avg_shift_o(cfg_avg_shift),
    .warmup_shots_o(cfg_warmup_shots),
    .n_min_o(cfg_nmin),
    .f_lo_o(cfg_flo),
    .f_hi_o(cfg_fhi),
    .threshold_o(threshold),
    .block_tol_o(block_tol),
    .search_mode_o(search_mode),
    .estop_hold_o(estop_hold),
    .estop_en_o(estop_en),
    .block_en_o(block_en),
    .short_confirm_o(short_confirm),
    .confirm_o(cfg_confirm),
    .ctrl_o(ctrl_word),
    .read_sel_o(read_sel),
    .commit_o(axi_commit),
    .target_o(axi_target),
    .bad_target_o(axi_bad_target)
  );

  wire pf_freq_valid;
  wire pf_finish;
  wire pf_waiting;
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
  wire [9:0] ac_log_entry;
  wire [63:0] ac_power;
  wire ac_power_valid;
  wire [31:0] ac_flags;
  reg [15:0] nconv_cnt;

  wire [31:0] eng_freq_word;
  wire eng_freq_valid;
  wire eng_probe_arm;
  wire eng_busy;
  wire eng_done;
  wire eng_converged;
  wire eng_capped;
  wire eng_nothing;
  wire eng_window;
  wire [31:0] eng_x;
  wire [15:0] eng_iter;
  wire [15:0] eng_points;
  wire [31:0] eng_spacing;
  wire [31:0] eng_jump;
  wire [31:0] eng_flags;

  wire eng_freq_ack = getfreq_rd & eng_freq_valid;

  reg finish_seen;

  always @(posedge clk) begin
    if (!rst_n)
      finish_seen <= 1'b0;
    else if (start_now)
      finish_seen <= 1'b0;
    else if (pf_finish)
      finish_seen <= 1'b1;
  end

  reg dest_r;

  always @(posedge clk) begin
    if (!rst_n)
      dest_r <= 1'b0;
    else if (start_now)
      dest_r <= 1'b0;
    else if (run_kw)
      dest_r <= 1'b1;
  end

  assign status_word = {pf_point_idx,
                        eng_freq_valid,
                        eng_busy,
                        eng_converged,
                        eng_capped,
                        dest_r,
                        estop_en,
                        eng_window,
                        ac_early_stop,
                        ac_warmup_done,
                        3'd0,
                        search_mode,
                        pf_waiting,
                        finish_seen,
                        (dest_r & eng_nothing)};

  reg res_pend;

  always @(posedge clk) begin
    if (!rst_n)
      res_pend <= 1'b0;
    else if (start_now | run_kw | clr_result)
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
      qtag_dt2_o <= {eng_iter, 12'd0, eng_window, eng_nothing, eng_capped, eng_converged};
      qtag_vld_o <= 1'b1;
    end else if (clr_result) begin
      qtag_vld_o <= 1'b0;
    end else if (status_rd & ~res_pend) begin
      qtag_dt1_o <= status_word;
      qtag_dt2_o <= best_freq;
      qtag_vld_o <= 1'b1;
    end else if (diag_rd & ~res_pend) begin
      qtag_dt1_o <= ac_n_used;
      qtag_dt2_o <= {nconv_cnt, 6'd0, ac_log_entry};
      qtag_vld_o <= 1'b1;
    end else if (getfreq_rd & ~res_pend) begin
      qtag_dt1_o <= eng_freq_word;
      qtag_dt2_o <= {31'd0, eng_freq_valid};
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
    else if (start_now | run_kw)
      qtag_rdy_o <= 1'b0;
    else if (pf_finish | eng_done)
      qtag_rdy_o <= 1'b1;
  end

  reg int_en;
  reg int_pulse;
  reg draining;
  reg arm_pend;
  reg [31:0] drain_drop_cnt;

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
    end else if (start_now | run_kw) begin
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
    end else if (start_now | run_kw) begin
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
    end else if (start_now | run_kw) begin
      drain_drop_cnt <= 32'd0;
    end else if (drain_now & s_axis_tvalid) begin
      drain_drop_cnt <= drain_drop_cnt + 32'd1;
    end
  end

  wire point_arm = (arm_req & ~drain_now) | (rearm_now & arm_pend);

  amplitude_calculator u_amplitude_calculator (
    .clk               (clk),
    .rst_n             (rst_n),
    .s_axis_tvalid     (s_axis_tvalid),
    .s_axis_tdata      (s_axis_tdata),
    .arm_i             (point_arm),
    .flush_i           (start_now | run_kw),
    .avg_shift_i       (cfg_avg_shift),
    .warmup_shots_i              (cfg_warmup_shots),
    .n_min_i           (cfg_nmin),
    .estop_en_i        (estop_en),
    .estop_hold_i      (estop_hold),
    .threshold_i       (threshold),
    .block_en_i        (block_en),
    .short_confirm_i   (short_confirm),
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
    .power_valid_o     (ac_power_valid),
    .debug_o           (ac_flags)
  );

  always @(posedge clk) begin
    if (!rst_n)
      nconv_cnt <= 16'd0;
    else if (start_now | run_kw)
      nconv_cnt <= 16'd0;
    else if (ac_log_wr & ~ac_log_entry[8])
      nconv_cnt <= nconv_cnt + 16'd1;
  end

  wire grid_valid = ac_power_valid & ~dest_r;
  wire search_valid = ac_power_valid & dest_r;

  gradient_engine u_gradient_engine (
    .clk               (clk),
    .rst_n             (rst_n),
    .start_i           (run_kw),
    .abort_i           (start_now),
    .dip_i             (search_mode),
    .start_freq_i      (cfg_start),
    .step_i            (cfg_step),
    .n_points_i        (cfg_npoints),
    .x0_i              (qtag_dt1_i),
    .f_lo_i            (cfg_flo),
    .f_hi_i            (cfg_fhi),
    .min_step_i        (qtag_dt3_i),
    .max_iteration_i   (qtag_dt4_i[15:0]),
    .threshold_i       (threshold),
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
    .nothing_o         (eng_nothing),
    .window_o          (eng_window),
    .x_o               (eng_x),
    .iteration_o       (eng_iter),
    .points_o          (eng_points),
    .spacing_o         (eng_spacing),
    .jump_o            (eng_jump),
    .debug_o           (eng_flags)
  );

  peak_finder u_peak_finder (
    .clk            (clk),
    .rst_n          (rst_n),
    .start_i        (start_now),
    .abort_i        (run_kw),
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
    .point_idx_o    (pf_point_idx),
    .waiting_o      (pf_waiting)
  );

  sweep_debug monitor (
    .clk              (clk),
    .rst_n            (rst_n),
    .read_sel_i       (read_sel),
    .job_start_i      (start_now | run_kw),
    .op_strobe_i      (en_rise),
    .op_i             (qtag_op_i),
    .op_unknown_i     (op_unknown),
    .read_held_i      ((status_rd | diag_rd | getfreq_rd | getmean_rd) & (res_pend | pf_finish | eng_done)),
    .getfreq_idle_i   (getfreq_rd & ~eng_freq_valid),
    .rdy_i            (qtag_rdy_o),
    .vld_i            (qtag_vld_o),
    .res_pend_i       (res_pend),
    .dest_i           (dest_r),
    .finish_seen_i    (finish_seen),
    .int_en_i         (int_en),
    .draining_i       (draining),
    .arm_pend_i       (arm_pend),
    .tvalid_i         (s_axis_tvalid),
    .drain_drop_cnt_i (drain_drop_cnt),
    .nconv_i          (nconv_cnt),
    .best_freq_i      (best_freq),
    .resp_dt1_i       (qtag_dt1_o),
    .resp_dt2_i       (qtag_dt2_o),
    .pf_waiting_i     (pf_waiting),
    .pf_freq_valid_i  (pf_freq_valid),
    .pf_point_idx_i   (pf_point_idx),
    .eng_flags_i      (eng_flags),
    .eng_spacing_i    (eng_spacing),
    .eng_freq_word_i  (eng_freq_word),
    .eng_x_i          (eng_x),
    .eng_iter_i       (eng_iter),
    .eng_points_i     (eng_points),
    .eng_jump_i       (eng_jump),
    .ac_flags_i       (ac_flags),
    .ac_power_i       (ac_power),
    .ac_power_valid_i (ac_power_valid),
    .ac_mean_i_i      (ac_mean_i),
    .ac_mean_q_i      (ac_mean_q),
    .ac_n_used_i      (ac_n_used),
    .ac_log_entry_i   (ac_log_entry),
    .cfg_start_i      (cfg_start),
    .cfg_step_i       (cfg_step),
    .cfg_npoints_i    (cfg_npoints),
    .cfg_avg_shift_i  (cfg_avg_shift),
    .cfg_warmup_i     (cfg_warmup_shots),
    .cfg_nmin_i       (cfg_nmin),
    .cfg_flo_i        (cfg_flo),
    .cfg_fhi_i        (cfg_fhi),
    .threshold_i      (threshold),
    .block_tol_i      (block_tol),
    .ctrl_i           (ctrl_word),
    .axi_commit_i     (axi_commit),
    .axi_target_i     (axi_target),
    .axi_bad_target_i (axi_bad_target),
    .view_dt1_o       (dbg_dt1),
    .view_dt2_o       (dbg_dt2)
  );

  assign c_debug_do = {en_rise, qtag_op_i,
                       qtag_rdy_o, qtag_vld_o, res_pend, dest_r, pf_waiting, finish_seen,
                       1'b0, eng_flags[16:12],
                       eng_freq_valid, eng_probe_arm, eng_done, pf_freq_valid, pf_finish,
                       ac_flags[5], ac_flags[4], ac_flags[0], ac_power_valid, ac_early_pulse,
                       int_pulse, draining, arm_pend, s_axis_tvalid};
  assign c_data_do = dbg_dt1;
  assign ps_debug_do = {s_axi_arready, s_axi_rready, s_axi_awready, s_axi_wready,
                        s_axi_arvalid, s_axi_rvalid, s_axi_awvalid, s_axi_wvalid,
                        s_axi_araddr[5:0], s_axi_awaddr[5:0],
                        s_axi_rdata[5:0], s_axi_wdata[5:0]};

endmodule
