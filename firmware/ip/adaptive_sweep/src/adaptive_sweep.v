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

  input t0_axis_tvalid,
  output t0_axis_tready,
  input [63:0] t0_axis_tdata,

  input t1_axis_tvalid,
  output t1_axis_tready,
  input [63:0] t1_axis_tdata,

  input t2_axis_tvalid,
  output t2_axis_tready,
  input [63:0] t2_axis_tdata,

  input t3_axis_tvalid,
  output t3_axis_tready,
  input [63:0] t3_axis_tdata,

  input t4_axis_tvalid,
  output t4_axis_tready,
  input [63:0] t4_axis_tdata,

  input t5_axis_tvalid,
  output t5_axis_tready,
  input [63:0] t5_axis_tdata,

  input t6_axis_tvalid,
  output t6_axis_tready,
  input [63:0] t6_axis_tdata,

  input t7_axis_tvalid,
  output t7_axis_tready,
  input [63:0] t7_axis_tdata,

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

  output [31:0] m_axi_awaddr,
  output [2:0] m_axi_awprot,
  output m_axi_awvalid,
  input m_axi_awready,
  output [31:0] m_axi_wdata,
  output [3:0] m_axi_wstrb,
  output m_axi_wvalid,
  input m_axi_wready,
  input [1:0] m_axi_bresp,
  input m_axi_bvalid,
  output m_axi_bready,
  output [31:0] m_axi_araddr,
  output [2:0] m_axi_arprot,
  output m_axi_arvalid,
  input m_axi_arready,
  input [31:0] m_axi_rdata,
  input [1:0] m_axi_rresp,
  input m_axi_rvalid,
  output m_axi_rready,

  output [31:0] c_debug_do,
  output [31:0] c_data_do,
  output [31:0] ps_debug_do
);

  localparam [4:0] OP_CFG_WINDOW = 5'd0;
  localparam [4:0] OP_CFG_ACQ = 5'd1;
  localparam [4:0] OP_CFG_GDKW = 5'd2;
  localparam [4:0] OP_CFG_TONES = 5'd3;
  localparam [4:0] OP_SEL_TONE = 5'd4;
  localparam [4:0] OP_CFG_RATIO = 5'd5;
  localparam [4:0] OP_START = 5'd8;
  localparam [4:0] OP_RUN_KW = 5'd9;
  localparam [4:0] OP_CLR_RESULT = 5'd10;
  localparam [4:0] OP_REARM = 5'd11;
  localparam [4:0] OP_CFG_INTERRUPT = 5'd15;
  localparam [4:0] OP_GET_FREQ = 5'd16;
  localparam [4:0] OP_GET_STATUS = 5'd17;
  localparam [4:0] OP_GET_DIAG = 5'd18;
  localparam [4:0] OP_GET_MEAN = 5'd19;
  localparam [4:0] OP_NEXT = 5'd20;
  localparam [4:0] OP_GET_RESULT = 5'd21;

  localparam [31:0] IDENT = 32'h4153_0600;

  assign s_axis_tready = 1'b1;
  assign t0_axis_tready = 1'b1;
  assign t1_axis_tready = 1'b1;
  assign t2_axis_tready = 1'b1;
  assign t3_axis_tready = 1'b1;
  assign t4_axis_tready = 1'b1;
  assign t5_axis_tready = 1'b1;
  assign t6_axis_tready = 1'b1;
  assign t7_axis_tready = 1'b1;

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
  wire cfg_tones = en_rise & (qtag_op_i == OP_CFG_TONES);
  wire sel_tone = en_rise & (qtag_op_i == OP_SEL_TONE);
  wire cfg_ratio = en_rise & (qtag_op_i == OP_CFG_RATIO);
  wire start_now = en_rise & (qtag_op_i == OP_START);
  wire run_kw = en_rise & (qtag_op_i == OP_RUN_KW);
  wire clr_result = en_rise & (qtag_op_i == OP_CLR_RESULT);
  wire rearm_now = en_rise & (qtag_op_i == OP_REARM);
  wire getfreq_rd = en_rise & (qtag_op_i == OP_GET_FREQ);
  wire status_rd = en_rise & (qtag_op_i == OP_GET_STATUS);
  wire diag_rd = en_rise & (qtag_op_i == OP_GET_DIAG);
  wire getmean_rd = en_rise & (qtag_op_i == OP_GET_MEAN);
  wire next_rd = en_rise & (qtag_op_i == OP_NEXT);
  wire result_rd = en_rise & (qtag_op_i == OP_GET_RESULT);
  wire op_decoded = cfg_sweep | cfg_meas | cfg_gdkw | start_now | run_kw |
                    clr_result | rearm_now | getfreq_rd | status_rd | diag_rd |
                    getmean_rd | cfg_tones | sel_tone | cfg_ratio | next_rd | result_rd;
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
  wire [31:0] cfg_x0;
  wire [31:0] cfg_gen_base;
  wire [36:0] cfg_ro_base;
  wire [34:0] cfg_ratio_word;
  wire [7:0] tone_mask;
  wire [2:0] tone_sel;
  wire mt = |tone_mask;

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
    .cfg_tones_i(cfg_tones),
    .sel_tone_i(sel_tone),
    .cfg_ratio_i(cfg_ratio),
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
    .x0_o(cfg_x0),
    .gen_base_o(cfg_gen_base),
    .ro_base_o(cfg_ro_base),
    .ratio_o(cfg_ratio_word),
    .tone_mask_o(tone_mask),
    .tone_sel_o(tone_sel),
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
  wire [31:0] pf_frequency;

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
  wire ac_early_pulse;
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

  reg finish_seen;
  reg dest_r;
  reg res_pend;

  localparam [1:0] G_IDLE = 2'd0;
  localparam [1:0] G_WAIT = 2'd1;
  localparam [1:0] G_WRITE = 2'd2;
  localparam [1:0] G_READY = 2'd3;

  reg [1:0] group_state, group_next;
  reg group_restart;
  reg [7:0] grid_pend;
  reg [7:0] finished;
  reg [7:0] armed_set;
  reg [7:0] over;
  reg point_open;

  wire [7:0] t_pf_freq_valid;
  wire [7:0] t_pf_finish;
  wire [7:0] t_eng_freq_valid;
  wire [7:0] t_eng_probe_arm;
  wire [7:0] t_eng_done;
  wire [7:0] t_early_pulse;
  wire [7:0] t_power_valid;

  wire [255:0] t_status;
  wire [255:0] t_best_freq;
  wire [255:0] t_n_used;
  wire [255:0] t_diag;
  wire [255:0] t_freq_word;
  wire [255:0] t_mean_i;
  wire [255:0] t_mean_q;
  wire [255:0] t_result;
  wire [255:0] t_result_flags;
  wire [255:0] t_next_freq;

  wire [31:0] gen_base_1;
  wire [36:0] ro_base_1;
  wire [34:0] ratio_1;
  wire [31:0] gen_base_2;
  wire [36:0] ro_base_2;
  wire [34:0] ratio_2;
  wire [31:0] gen_base_3;
  wire [36:0] ro_base_3;
  wire [34:0] ratio_3;
  wire [31:0] gen_base_4;
  wire [36:0] ro_base_4;
  wire [34:0] ratio_4;
  wire [31:0] gen_base_5;
  wire [36:0] ro_base_5;
  wire [34:0] ratio_5;
  wire [31:0] gen_base_6;
  wire [36:0] ro_base_6;
  wire [34:0] ratio_6;
  wire [31:0] gen_base_7;
  wire [36:0] ro_base_7;
  wire [34:0] ratio_7;

  wire job_start = start_now | run_kw;
  wire [7:0] t_new = dest_r ? t_eng_freq_valid : grid_pend;
  wire [7:0] write_mask = tone_mask & ~finished & t_new;
  wire all_ready = &(~tone_mask | finished | t_new);
  wire any_new = |write_mask;
  wire group_decide = mt & (group_state == G_WAIT) & all_ready & ~job_start;
  wire writer_start = group_decide & any_new;
  wire group_finish = group_decide & ~any_new;
  wire writer_done;
  wire next_ack = next_rd & (group_state == G_READY) & ~res_pend;

  always @(posedge clk) begin
    if (!rst_n)
      group_state <= G_IDLE;
    else
      group_state <= group_next;
  end

  always @(*) begin
    group_next = group_state;
    case (group_state)
      G_IDLE: group_next = (job_start & mt) ? G_WAIT : G_IDLE;
      G_WAIT: group_next = job_start ? G_WAIT : (~all_ready ? G_WAIT : (any_new ? G_WRITE : G_IDLE));
      G_WRITE: group_next = ~writer_done ? G_WRITE : ((group_restart | job_start) ? G_WAIT : G_READY);
      G_READY: group_next = job_start ? G_WAIT : (next_ack ? G_WAIT : G_READY);
    endcase
  end

  always @(posedge clk) begin
    if (!rst_n)
      group_restart <= 1'b0;
    else if (group_state != G_WRITE)
      group_restart <= 1'b0;
    else if (job_start)
      group_restart <= 1'b1;
  end

  always @(posedge clk) begin
    if (!rst_n)
      grid_pend <= 8'd0;
    else if (job_start | next_ack)
      grid_pend <= 8'd0;
    else
      grid_pend <= grid_pend | (t_pf_freq_valid & tone_mask);
  end

  always @(posedge clk) begin
    if (!rst_n)
      finished <= 8'd0;
    else if (job_start)
      finished <= 8'd0;
    else
      finished <= finished | ((t_pf_finish | t_eng_done) & tone_mask);
  end

  wire [7:0] mt_arm = (next_ack ? grid_pend : 8'd0) | (t_eng_probe_arm & tone_mask);
  wire [7:0] over_next = over | ((t_early_pulse | t_power_valid) & armed_set);
  wire point_done = point_open & (over_next == armed_set);
  wire group_early = point_done & (|(t_early_pulse & armed_set));

  always @(posedge clk) begin
    if (!rst_n) begin
      armed_set <= 8'd0;
      over <= 8'd0;
      point_open <= 1'b0;
    end else if (job_start) begin
      armed_set <= 8'd0;
      over <= 8'd0;
      point_open <= 1'b0;
    end else if (next_ack) begin
      armed_set <= mt_arm;
      over <= 8'd0;
      point_open <= |mt_arm;
    end else if (|mt_arm) begin
      armed_set <= armed_set | mt_arm;
      point_open <= 1'b1;
    end else begin
      over <= over_next;
      if (point_done)
        point_open <= 1'b0;
    end
  end

  wire grid_finish = ~mt & pf_finish;
  wire kw_finish = ~mt & eng_done;
  wire job_finish = grid_finish | kw_finish | group_finish;

  wire eng_freq_ack = (mt ? next_ack : getfreq_rd) & eng_freq_valid;

  always @(posedge clk) begin
    if (!rst_n)
      finish_seen <= 1'b0;
    else if (start_now)
      finish_seen <= 1'b0;
    else if (grid_finish | (group_finish & ~dest_r))
      finish_seen <= 1'b1;
  end

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

  assign t_pf_freq_valid[0] = pf_freq_valid;
  assign t_pf_finish[0] = pf_finish;
  assign t_eng_freq_valid[0] = eng_freq_valid;
  assign t_eng_probe_arm[0] = eng_probe_arm;
  assign t_eng_done[0] = eng_done;
  assign t_early_pulse[0] = ac_early_pulse;
  assign t_power_valid[0] = ac_power_valid;

  assign t_status[31:0] = status_word;
  assign t_best_freq[31:0] = best_freq;
  assign t_n_used[31:0] = ac_n_used;
  assign t_diag[31:0] = {nconv_cnt, 6'd0, ac_log_entry};
  assign t_freq_word[31:0] = eng_freq_word;
  assign t_mean_i[31:0] = dest_r ? ac_mean_i : pf_best_mean_i;
  assign t_mean_q[31:0] = dest_r ? ac_mean_q : pf_best_mean_q;
  assign t_result[31:0] = dest_r ? eng_x : best_freq;
  assign t_result_flags[31:0] = dest_r ? {eng_iter, 12'd0, eng_window, eng_nothing, eng_capped, eng_converged} : 32'd0;
  assign t_next_freq[31:0] = dest_r ? eng_freq_word : pf_frequency;

  wire [31:0] sel_status = t_status[{tone_sel, 5'd0} +: 32];
  wire [31:0] sel_best_freq = t_best_freq[{tone_sel, 5'd0} +: 32];
  wire [31:0] sel_n_used = t_n_used[{tone_sel, 5'd0} +: 32];
  wire [31:0] sel_diag = t_diag[{tone_sel, 5'd0} +: 32];
  wire [31:0] sel_freq_word = t_freq_word[{tone_sel, 5'd0} +: 32];
  wire [31:0] sel_mean_i = t_mean_i[{tone_sel, 5'd0} +: 32];
  wire [31:0] sel_mean_q = t_mean_q[{tone_sel, 5'd0} +: 32];
  wire [31:0] sel_result = t_result[{tone_sel, 5'd0} +: 32];
  wire [31:0] sel_result_flags = t_result_flags[{tone_sel, 5'd0} +: 32];
  wire sel_freq_valid = t_eng_freq_valid[tone_sel];

  always @(posedge clk) begin
    if (!rst_n)
      res_pend <= 1'b0;
    else if (start_now | run_kw | clr_result)
      res_pend <= 1'b0;
    else if (job_finish)
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
    end else if (grid_finish) begin
      qtag_dt1_o <= best_freq;
      qtag_dt2_o <= 32'd0;
      qtag_vld_o <= 1'b1;
    end else if (kw_finish) begin
      qtag_dt1_o <= eng_x;
      qtag_dt2_o <= {eng_iter, 12'd0, eng_window, eng_nothing, eng_capped, eng_converged};
      qtag_vld_o <= 1'b1;
    end else if (group_finish) begin
      qtag_dt1_o <= sel_result;
      qtag_dt2_o <= sel_result_flags;
      qtag_vld_o <= 1'b1;
    end else if (clr_result) begin
      qtag_vld_o <= 1'b0;
    end else if (status_rd & ~res_pend) begin
      qtag_dt1_o <= sel_status;
      qtag_dt2_o <= sel_best_freq;
      qtag_vld_o <= 1'b1;
    end else if (diag_rd & ~res_pend) begin
      qtag_dt1_o <= sel_n_used;
      qtag_dt2_o <= sel_diag;
      qtag_vld_o <= 1'b1;
    end else if (getfreq_rd & ~res_pend) begin
      qtag_dt1_o <= sel_freq_word;
      qtag_dt2_o <= {31'd0, sel_freq_valid};
      qtag_vld_o <= 1'b1;
    end else if (getmean_rd & ~res_pend) begin
      qtag_dt1_o <= sel_mean_i;
      qtag_dt2_o <= sel_mean_q;
      qtag_vld_o <= 1'b1;
    end else if (next_rd & ~res_pend) begin
      qtag_dt1_o <= {16'd0, finished, tone_mask};
      qtag_dt2_o <= {31'd0, (group_state == G_READY)};
      qtag_vld_o <= 1'b1;
    end else if (result_rd & ~res_pend) begin
      qtag_dt1_o <= sel_result;
      qtag_dt2_o <= sel_result_flags;
      qtag_vld_o <= 1'b1;
    end
  end

  always @(posedge clk) begin
    if (!rst_n)
      qtag_rdy_o <= 1'b1;
    else if (start_now | run_kw)
      qtag_rdy_o <= 1'b0;
    else if (job_finish)
      qtag_rdy_o <= 1'b1;
  end

  reg int_en;
  reg int_pulse;
  reg draining;
  reg arm_pend;
  reg [31:0] drain_drop_cnt;

  wire drain_set = (mt ? group_early : ac_early_pulse) & int_en;
  wire drain_now = draining & ~rearm_now;
  wire arm_req = ~mt & (pf_freq_valid | eng_probe_arm);

  wire ac_tvalid = mt ? (t0_axis_tvalid & tone_mask[0]) : s_axis_tvalid;
  wire [63:0] ac_tdata = mt ? t0_axis_tdata : s_axis_tdata;

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
    end else if (drain_now & ac_tvalid) begin
      drain_drop_cnt <= drain_drop_cnt + 32'd1;
    end
  end

  wire point_arm = mt ? mt_arm[0] : ((arm_req & ~drain_now) | (rearm_now & arm_pend));

  amplitude_calculator u_amplitude_calculator (
    .clk               (clk),
    .rst_n             (rst_n),
    .s_axis_tvalid     (ac_tvalid),
    .s_axis_tdata      (ac_tdata),
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
    .start_i           (run_kw & (tone_mask[0] | ~mt)),
    .abort_i           (start_now),
    .dip_i             (search_mode),
    .start_freq_i      (cfg_start),
    .step_i            (cfg_step),
    .n_points_i        (cfg_npoints),
    .x0_i              (mt ? cfg_x0 : qtag_dt1_i),
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
    .start_i        (start_now & (tone_mask[0] | ~mt)),
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
    .frequency_o    (pf_frequency),
    .waiting_o      (pf_waiting)
  );

  tone_core tone_1 (
    .clk               (clk),
    .rst_n             (rst_n),
    .enable_i          (tone_mask[1]),
    .select_i          (tone_sel == 3'd1),
    .cfg_sweep_i       (cfg_sweep),
    .cfg_search_i      (cfg_gdkw),
    .cfg_ratio_i       (cfg_ratio),
    .dt1_i             (qtag_dt1_i),
    .dt2_i             (qtag_dt2_i),
    .dt3_i             (qtag_dt3_i),
    .dt4_i             (qtag_dt4_i),
    .start_i           (start_now),
    .run_kw_i          (run_kw),
    .arm_i             (mt_arm[1]),
    .freq_ack_i        (next_ack & t_eng_freq_valid[1]),
    .dest_i            (dest_r),
    .finish_seen_i     (finish_seen),
    .s_axis_tvalid     (t1_axis_tvalid),
    .s_axis_tdata      (t1_axis_tdata),
    .step_i            (cfg_step),
    .n_points_i        (cfg_npoints),
    .avg_shift_i       (cfg_avg_shift),
    .warmup_shots_i    (cfg_warmup_shots),
    .n_min_i           (cfg_nmin),
    .search_mode_i     (search_mode),
    .estop_en_i        (estop_en),
    .estop_hold_i      (estop_hold),
    .threshold_i       (threshold),
    .block_en_i        (block_en),
    .short_confirm_i   (short_confirm),
    .block_tol_i       (block_tol),
    .confirm_i         (cfg_confirm),
    .min_step_i        (qtag_dt3_i),
    .max_iteration_i   (qtag_dt4_i[15:0]),
    .pf_freq_valid_o   (t_pf_freq_valid[1]),
    .pf_finish_o       (t_pf_finish[1]),
    .eng_freq_valid_o  (t_eng_freq_valid[1]),
    .eng_probe_arm_o   (t_eng_probe_arm[1]),
    .eng_done_o        (t_eng_done[1]),
    .early_pulse_o     (t_early_pulse[1]),
    .power_valid_o     (t_power_valid[1]),
    .status_o          (t_status[63:32]),
    .best_freq_o       (t_best_freq[63:32]),
    .n_used_o          (t_n_used[63:32]),
    .diag_o            (t_diag[63:32]),
    .freq_word_o       (t_freq_word[63:32]),
    .mean_i_o          (t_mean_i[63:32]),
    .mean_q_o          (t_mean_q[63:32]),
    .result_o          (t_result[63:32]),
    .result_flags_o    (t_result_flags[63:32]),
    .next_freq_o       (t_next_freq[63:32]),
    .gen_base_o        (gen_base_1),
    .ro_base_o         (ro_base_1),
    .ratio_o           (ratio_1)
  );

  tone_core tone_2 (
    .clk               (clk),
    .rst_n             (rst_n),
    .enable_i          (tone_mask[2]),
    .select_i          (tone_sel == 3'd2),
    .cfg_sweep_i       (cfg_sweep),
    .cfg_search_i      (cfg_gdkw),
    .cfg_ratio_i       (cfg_ratio),
    .dt1_i             (qtag_dt1_i),
    .dt2_i             (qtag_dt2_i),
    .dt3_i             (qtag_dt3_i),
    .dt4_i             (qtag_dt4_i),
    .start_i           (start_now),
    .run_kw_i          (run_kw),
    .arm_i             (mt_arm[2]),
    .freq_ack_i        (next_ack & t_eng_freq_valid[2]),
    .dest_i            (dest_r),
    .finish_seen_i     (finish_seen),
    .s_axis_tvalid     (t2_axis_tvalid),
    .s_axis_tdata      (t2_axis_tdata),
    .step_i            (cfg_step),
    .n_points_i        (cfg_npoints),
    .avg_shift_i       (cfg_avg_shift),
    .warmup_shots_i    (cfg_warmup_shots),
    .n_min_i           (cfg_nmin),
    .search_mode_i     (search_mode),
    .estop_en_i        (estop_en),
    .estop_hold_i      (estop_hold),
    .threshold_i       (threshold),
    .block_en_i        (block_en),
    .short_confirm_i   (short_confirm),
    .block_tol_i       (block_tol),
    .confirm_i         (cfg_confirm),
    .min_step_i        (qtag_dt3_i),
    .max_iteration_i   (qtag_dt4_i[15:0]),
    .pf_freq_valid_o   (t_pf_freq_valid[2]),
    .pf_finish_o       (t_pf_finish[2]),
    .eng_freq_valid_o  (t_eng_freq_valid[2]),
    .eng_probe_arm_o   (t_eng_probe_arm[2]),
    .eng_done_o        (t_eng_done[2]),
    .early_pulse_o     (t_early_pulse[2]),
    .power_valid_o     (t_power_valid[2]),
    .status_o          (t_status[95:64]),
    .best_freq_o       (t_best_freq[95:64]),
    .n_used_o          (t_n_used[95:64]),
    .diag_o            (t_diag[95:64]),
    .freq_word_o       (t_freq_word[95:64]),
    .mean_i_o          (t_mean_i[95:64]),
    .mean_q_o          (t_mean_q[95:64]),
    .result_o          (t_result[95:64]),
    .result_flags_o    (t_result_flags[95:64]),
    .next_freq_o       (t_next_freq[95:64]),
    .gen_base_o        (gen_base_2),
    .ro_base_o         (ro_base_2),
    .ratio_o           (ratio_2)
  );

  tone_core tone_3 (
    .clk               (clk),
    .rst_n             (rst_n),
    .enable_i          (tone_mask[3]),
    .select_i          (tone_sel == 3'd3),
    .cfg_sweep_i       (cfg_sweep),
    .cfg_search_i      (cfg_gdkw),
    .cfg_ratio_i       (cfg_ratio),
    .dt1_i             (qtag_dt1_i),
    .dt2_i             (qtag_dt2_i),
    .dt3_i             (qtag_dt3_i),
    .dt4_i             (qtag_dt4_i),
    .start_i           (start_now),
    .run_kw_i          (run_kw),
    .arm_i             (mt_arm[3]),
    .freq_ack_i        (next_ack & t_eng_freq_valid[3]),
    .dest_i            (dest_r),
    .finish_seen_i     (finish_seen),
    .s_axis_tvalid     (t3_axis_tvalid),
    .s_axis_tdata      (t3_axis_tdata),
    .step_i            (cfg_step),
    .n_points_i        (cfg_npoints),
    .avg_shift_i       (cfg_avg_shift),
    .warmup_shots_i    (cfg_warmup_shots),
    .n_min_i           (cfg_nmin),
    .search_mode_i     (search_mode),
    .estop_en_i        (estop_en),
    .estop_hold_i      (estop_hold),
    .threshold_i       (threshold),
    .block_en_i        (block_en),
    .short_confirm_i   (short_confirm),
    .block_tol_i       (block_tol),
    .confirm_i         (cfg_confirm),
    .min_step_i        (qtag_dt3_i),
    .max_iteration_i   (qtag_dt4_i[15:0]),
    .pf_freq_valid_o   (t_pf_freq_valid[3]),
    .pf_finish_o       (t_pf_finish[3]),
    .eng_freq_valid_o  (t_eng_freq_valid[3]),
    .eng_probe_arm_o   (t_eng_probe_arm[3]),
    .eng_done_o        (t_eng_done[3]),
    .early_pulse_o     (t_early_pulse[3]),
    .power_valid_o     (t_power_valid[3]),
    .status_o          (t_status[127:96]),
    .best_freq_o       (t_best_freq[127:96]),
    .n_used_o          (t_n_used[127:96]),
    .diag_o            (t_diag[127:96]),
    .freq_word_o       (t_freq_word[127:96]),
    .mean_i_o          (t_mean_i[127:96]),
    .mean_q_o          (t_mean_q[127:96]),
    .result_o          (t_result[127:96]),
    .result_flags_o    (t_result_flags[127:96]),
    .next_freq_o       (t_next_freq[127:96]),
    .gen_base_o        (gen_base_3),
    .ro_base_o         (ro_base_3),
    .ratio_o           (ratio_3)
  );

  tone_core tone_4 (
    .clk               (clk),
    .rst_n             (rst_n),
    .enable_i          (tone_mask[4]),
    .select_i          (tone_sel == 3'd4),
    .cfg_sweep_i       (cfg_sweep),
    .cfg_search_i      (cfg_gdkw),
    .cfg_ratio_i       (cfg_ratio),
    .dt1_i             (qtag_dt1_i),
    .dt2_i             (qtag_dt2_i),
    .dt3_i             (qtag_dt3_i),
    .dt4_i             (qtag_dt4_i),
    .start_i           (start_now),
    .run_kw_i          (run_kw),
    .arm_i             (mt_arm[4]),
    .freq_ack_i        (next_ack & t_eng_freq_valid[4]),
    .dest_i            (dest_r),
    .finish_seen_i     (finish_seen),
    .s_axis_tvalid     (t4_axis_tvalid),
    .s_axis_tdata      (t4_axis_tdata),
    .step_i            (cfg_step),
    .n_points_i        (cfg_npoints),
    .avg_shift_i       (cfg_avg_shift),
    .warmup_shots_i    (cfg_warmup_shots),
    .n_min_i           (cfg_nmin),
    .search_mode_i     (search_mode),
    .estop_en_i        (estop_en),
    .estop_hold_i      (estop_hold),
    .threshold_i       (threshold),
    .block_en_i        (block_en),
    .short_confirm_i   (short_confirm),
    .block_tol_i       (block_tol),
    .confirm_i         (cfg_confirm),
    .min_step_i        (qtag_dt3_i),
    .max_iteration_i   (qtag_dt4_i[15:0]),
    .pf_freq_valid_o   (t_pf_freq_valid[4]),
    .pf_finish_o       (t_pf_finish[4]),
    .eng_freq_valid_o  (t_eng_freq_valid[4]),
    .eng_probe_arm_o   (t_eng_probe_arm[4]),
    .eng_done_o        (t_eng_done[4]),
    .early_pulse_o     (t_early_pulse[4]),
    .power_valid_o     (t_power_valid[4]),
    .status_o          (t_status[159:128]),
    .best_freq_o       (t_best_freq[159:128]),
    .n_used_o          (t_n_used[159:128]),
    .diag_o            (t_diag[159:128]),
    .freq_word_o       (t_freq_word[159:128]),
    .mean_i_o          (t_mean_i[159:128]),
    .mean_q_o          (t_mean_q[159:128]),
    .result_o          (t_result[159:128]),
    .result_flags_o    (t_result_flags[159:128]),
    .next_freq_o       (t_next_freq[159:128]),
    .gen_base_o        (gen_base_4),
    .ro_base_o         (ro_base_4),
    .ratio_o           (ratio_4)
  );

  tone_core tone_5 (
    .clk               (clk),
    .rst_n             (rst_n),
    .enable_i          (tone_mask[5]),
    .select_i          (tone_sel == 3'd5),
    .cfg_sweep_i       (cfg_sweep),
    .cfg_search_i      (cfg_gdkw),
    .cfg_ratio_i       (cfg_ratio),
    .dt1_i             (qtag_dt1_i),
    .dt2_i             (qtag_dt2_i),
    .dt3_i             (qtag_dt3_i),
    .dt4_i             (qtag_dt4_i),
    .start_i           (start_now),
    .run_kw_i          (run_kw),
    .arm_i             (mt_arm[5]),
    .freq_ack_i        (next_ack & t_eng_freq_valid[5]),
    .dest_i            (dest_r),
    .finish_seen_i     (finish_seen),
    .s_axis_tvalid     (t5_axis_tvalid),
    .s_axis_tdata      (t5_axis_tdata),
    .step_i            (cfg_step),
    .n_points_i        (cfg_npoints),
    .avg_shift_i       (cfg_avg_shift),
    .warmup_shots_i    (cfg_warmup_shots),
    .n_min_i           (cfg_nmin),
    .search_mode_i     (search_mode),
    .estop_en_i        (estop_en),
    .estop_hold_i      (estop_hold),
    .threshold_i       (threshold),
    .block_en_i        (block_en),
    .short_confirm_i   (short_confirm),
    .block_tol_i       (block_tol),
    .confirm_i         (cfg_confirm),
    .min_step_i        (qtag_dt3_i),
    .max_iteration_i   (qtag_dt4_i[15:0]),
    .pf_freq_valid_o   (t_pf_freq_valid[5]),
    .pf_finish_o       (t_pf_finish[5]),
    .eng_freq_valid_o  (t_eng_freq_valid[5]),
    .eng_probe_arm_o   (t_eng_probe_arm[5]),
    .eng_done_o        (t_eng_done[5]),
    .early_pulse_o     (t_early_pulse[5]),
    .power_valid_o     (t_power_valid[5]),
    .status_o          (t_status[191:160]),
    .best_freq_o       (t_best_freq[191:160]),
    .n_used_o          (t_n_used[191:160]),
    .diag_o            (t_diag[191:160]),
    .freq_word_o       (t_freq_word[191:160]),
    .mean_i_o          (t_mean_i[191:160]),
    .mean_q_o          (t_mean_q[191:160]),
    .result_o          (t_result[191:160]),
    .result_flags_o    (t_result_flags[191:160]),
    .next_freq_o       (t_next_freq[191:160]),
    .gen_base_o        (gen_base_5),
    .ro_base_o         (ro_base_5),
    .ratio_o           (ratio_5)
  );

  tone_core tone_6 (
    .clk               (clk),
    .rst_n             (rst_n),
    .enable_i          (tone_mask[6]),
    .select_i          (tone_sel == 3'd6),
    .cfg_sweep_i       (cfg_sweep),
    .cfg_search_i      (cfg_gdkw),
    .cfg_ratio_i       (cfg_ratio),
    .dt1_i             (qtag_dt1_i),
    .dt2_i             (qtag_dt2_i),
    .dt3_i             (qtag_dt3_i),
    .dt4_i             (qtag_dt4_i),
    .start_i           (start_now),
    .run_kw_i          (run_kw),
    .arm_i             (mt_arm[6]),
    .freq_ack_i        (next_ack & t_eng_freq_valid[6]),
    .dest_i            (dest_r),
    .finish_seen_i     (finish_seen),
    .s_axis_tvalid     (t6_axis_tvalid),
    .s_axis_tdata      (t6_axis_tdata),
    .step_i            (cfg_step),
    .n_points_i        (cfg_npoints),
    .avg_shift_i       (cfg_avg_shift),
    .warmup_shots_i    (cfg_warmup_shots),
    .n_min_i           (cfg_nmin),
    .search_mode_i     (search_mode),
    .estop_en_i        (estop_en),
    .estop_hold_i      (estop_hold),
    .threshold_i       (threshold),
    .block_en_i        (block_en),
    .short_confirm_i   (short_confirm),
    .block_tol_i       (block_tol),
    .confirm_i         (cfg_confirm),
    .min_step_i        (qtag_dt3_i),
    .max_iteration_i   (qtag_dt4_i[15:0]),
    .pf_freq_valid_o   (t_pf_freq_valid[6]),
    .pf_finish_o       (t_pf_finish[6]),
    .eng_freq_valid_o  (t_eng_freq_valid[6]),
    .eng_probe_arm_o   (t_eng_probe_arm[6]),
    .eng_done_o        (t_eng_done[6]),
    .early_pulse_o     (t_early_pulse[6]),
    .power_valid_o     (t_power_valid[6]),
    .status_o          (t_status[223:192]),
    .best_freq_o       (t_best_freq[223:192]),
    .n_used_o          (t_n_used[223:192]),
    .diag_o            (t_diag[223:192]),
    .freq_word_o       (t_freq_word[223:192]),
    .mean_i_o          (t_mean_i[223:192]),
    .mean_q_o          (t_mean_q[223:192]),
    .result_o          (t_result[223:192]),
    .result_flags_o    (t_result_flags[223:192]),
    .next_freq_o       (t_next_freq[223:192]),
    .gen_base_o        (gen_base_6),
    .ro_base_o         (ro_base_6),
    .ratio_o           (ratio_6)
  );

  tone_core tone_7 (
    .clk               (clk),
    .rst_n             (rst_n),
    .enable_i          (tone_mask[7]),
    .select_i          (tone_sel == 3'd7),
    .cfg_sweep_i       (cfg_sweep),
    .cfg_search_i      (cfg_gdkw),
    .cfg_ratio_i       (cfg_ratio),
    .dt1_i             (qtag_dt1_i),
    .dt2_i             (qtag_dt2_i),
    .dt3_i             (qtag_dt3_i),
    .dt4_i             (qtag_dt4_i),
    .start_i           (start_now),
    .run_kw_i          (run_kw),
    .arm_i             (mt_arm[7]),
    .freq_ack_i        (next_ack & t_eng_freq_valid[7]),
    .dest_i            (dest_r),
    .finish_seen_i     (finish_seen),
    .s_axis_tvalid     (t7_axis_tvalid),
    .s_axis_tdata      (t7_axis_tdata),
    .step_i            (cfg_step),
    .n_points_i        (cfg_npoints),
    .avg_shift_i       (cfg_avg_shift),
    .warmup_shots_i    (cfg_warmup_shots),
    .n_min_i           (cfg_nmin),
    .search_mode_i     (search_mode),
    .estop_en_i        (estop_en),
    .estop_hold_i      (estop_hold),
    .threshold_i       (threshold),
    .block_en_i        (block_en),
    .short_confirm_i   (short_confirm),
    .block_tol_i       (block_tol),
    .confirm_i         (cfg_confirm),
    .min_step_i        (qtag_dt3_i),
    .max_iteration_i   (qtag_dt4_i[15:0]),
    .pf_freq_valid_o   (t_pf_freq_valid[7]),
    .pf_finish_o       (t_pf_finish[7]),
    .eng_freq_valid_o  (t_eng_freq_valid[7]),
    .eng_probe_arm_o   (t_eng_probe_arm[7]),
    .eng_done_o        (t_eng_done[7]),
    .early_pulse_o     (t_early_pulse[7]),
    .power_valid_o     (t_power_valid[7]),
    .status_o          (t_status[255:224]),
    .best_freq_o       (t_best_freq[255:224]),
    .n_used_o          (t_n_used[255:224]),
    .diag_o            (t_diag[255:224]),
    .freq_word_o       (t_freq_word[255:224]),
    .mean_i_o          (t_mean_i[255:224]),
    .mean_q_o          (t_mean_q[255:224]),
    .result_o          (t_result[255:224]),
    .result_flags_o    (t_result_flags[255:224]),
    .next_freq_o       (t_next_freq[255:224]),
    .gen_base_o        (gen_base_7),
    .ro_base_o         (ro_base_7),
    .ratio_o           (ratio_7)
  );

  wire [2:0] writer_tone;
  wire [31:0] writer_freq = t_next_freq[{writer_tone, 5'd0} +: 32];
  reg [31:0] writer_gen_base;
  reg [36:0] writer_ro_base;
  reg [34:0] writer_ratio;

  always @(*) begin
    case (writer_tone)
      3'd0: begin writer_gen_base = cfg_gen_base; writer_ro_base = cfg_ro_base; writer_ratio = cfg_ratio_word; end
      3'd1: begin writer_gen_base = gen_base_1; writer_ro_base = ro_base_1; writer_ratio = ratio_1; end
      3'd2: begin writer_gen_base = gen_base_2; writer_ro_base = ro_base_2; writer_ratio = ratio_2; end
      3'd3: begin writer_gen_base = gen_base_3; writer_ro_base = ro_base_3; writer_ratio = ratio_3; end
      3'd4: begin writer_gen_base = gen_base_4; writer_ro_base = ro_base_4; writer_ratio = ratio_4; end
      3'd5: begin writer_gen_base = gen_base_5; writer_ro_base = ro_base_5; writer_ratio = ratio_5; end
      3'd6: begin writer_gen_base = gen_base_6; writer_ro_base = ro_base_6; writer_ratio = ratio_6; end
      3'd7: begin writer_gen_base = gen_base_7; writer_ro_base = ro_base_7; writer_ratio = ratio_7; end
    endcase
  end

  tone_writer writer (
    .clk            (clk),
    .rst_n          (rst_n),
    .start_i        (writer_start),
    .mask_i         (write_mask),
    .done_o         (writer_done),
    .tone_o         (writer_tone),
    .freq_i         (writer_freq),
    .gen_base_i     (writer_gen_base),
    .ro_base_i      (writer_ro_base),
    .ratio_i        (writer_ratio),
    .m_axi_awaddr   (m_axi_awaddr),
    .m_axi_awprot   (m_axi_awprot),
    .m_axi_awvalid  (m_axi_awvalid),
    .m_axi_awready  (m_axi_awready),
    .m_axi_wdata    (m_axi_wdata),
    .m_axi_wstrb    (m_axi_wstrb),
    .m_axi_wvalid   (m_axi_wvalid),
    .m_axi_wready   (m_axi_wready),
    .m_axi_bresp    (m_axi_bresp),
    .m_axi_bvalid   (m_axi_bvalid),
    .m_axi_bready   (m_axi_bready),
    .m_axi_araddr   (m_axi_araddr),
    .m_axi_arprot   (m_axi_arprot),
    .m_axi_arvalid  (m_axi_arvalid),
    .m_axi_arready  (m_axi_arready),
    .m_axi_rdata    (m_axi_rdata),
    .m_axi_rresp    (m_axi_rresp),
    .m_axi_rvalid   (m_axi_rvalid),
    .m_axi_rready   (m_axi_rready)
  );

  sweep_debug monitor (
    .clk              (clk),
    .rst_n            (rst_n),
    .read_sel_i       (read_sel),
    .job_start_i      (start_now | run_kw),
    .op_strobe_i      (en_rise),
    .op_i             (qtag_op_i),
    .op_unknown_i     (op_unknown),
    .read_held_i      ((status_rd | diag_rd | getfreq_rd | getmean_rd | next_rd | result_rd) & (res_pend | job_finish)),
    .getfreq_idle_i   (getfreq_rd & ~eng_freq_valid),
    .rdy_i            (qtag_rdy_o),
    .vld_i            (qtag_vld_o),
    .res_pend_i       (res_pend),
    .dest_i           (dest_r),
    .finish_seen_i    (finish_seen),
    .int_en_i         (int_en),
    .draining_i       (draining),
    .arm_pend_i       (arm_pend),
    .tvalid_i         (ac_tvalid),
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
                       int_pulse, draining, arm_pend, ac_tvalid};
  assign c_data_do = dbg_dt1;
  assign ps_debug_do = {s_axi_arready, s_axi_rready, s_axi_awready, s_axi_wready,
                        s_axi_arvalid, s_axi_rvalid, s_axi_awvalid, s_axi_wvalid,
                        s_axi_araddr[5:0], s_axi_awaddr[5:0],
                        s_axi_rdata[5:0], s_axi_wdata[5:0]};

endmodule
