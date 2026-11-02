`timescale 1ns / 1ps

module register_bank(
  input clk,
  input rst_n,

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

  input cfg_sweep_i,
  input cfg_meas_i,
  input cfg_search_i,
  input [31:0] dt1_i,
  input [31:0] dt2_i,
  input [31:0] dt3_i,
  input [31:0] dt4_i,

  input [31:0] status_i,
  input [31:0] view_dt1_i,
  input [31:0] view_dt2_i,
  input [31:0] ident_i,

  output reg [31:0] start_freq_o,
  output reg [31:0] step_o,
  output reg [15:0] n_points_o,
  output reg [4:0] avg_shift_o,
  output reg [31:0] warmup_shots_o,
  output reg [31:0] n_min_o,
  output reg [31:0] f_lo_o,
  output reg [31:0] f_hi_o,
  output reg [15:0] threshold_o,
  output reg [31:0] block_tol_o,

  output search_mode_o,
  output estop_hold_o,
  output estop_en_o,
  output block_en_o,
  output short_confirm_o,
  output [2:0] confirm_o,
  output [31:0] ctrl_o,

  output [3:0] read_sel_o,
  output commit_o,
  output [4:0] target_o,
  output bad_target_o
);

  wire [31:0] reg0;
  wire [31:0] reg1;
  wire [31:0] reg2;

  reg [31:0] dbg_status_axi;
  reg [31:0] dbg_dt1_axi;
  reg [31:0] dbg_dt2_axi;

  axi_slv_adaptive_sweep axi_slave(
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
    .REG0_REG(reg0),
    .REG1_REG(reg1),
    .REG2_REG(reg2),
    .REG3_IN(dbg_status_axi),
    .REG4_IN(dbg_dt1_axi),
    .REG5_IN(dbg_dt2_axi),
    .REG6_IN(ident_i)
  );

  always @(posedge s_axi_aclk) begin
    if (!s_axi_aresetn) begin
      dbg_status_axi <= 32'd0;
      dbg_dt1_axi <= 32'd0;
      dbg_dt2_axi <= 32'd0;
    end else begin
      dbg_status_axi <= status_i;
      dbg_dt1_axi <= view_dt1_i;
      dbg_dt2_axi <= view_dt2_i;
    end
  end

  (* ASYNC_REG = "TRUE" *) reg [3:0] read_sel_s0;
  (* ASYNC_REG = "TRUE" *) reg [3:0] read_sel_s1;

  always @(posedge clk) begin
    if (!rst_n) begin
      read_sel_s0 <= 4'd0;
      read_sel_s1 <= 4'd0;
    end else begin
      read_sel_s0 <= reg2[3:0];
      read_sel_s1 <= read_sel_s0;
    end
  end

  assign read_sel_o = read_sel_s1;

  (* ASYNC_REG = "TRUE" *) reg toggle_s0;
  (* ASYNC_REG = "TRUE" *) reg toggle_s1;
  reg toggle_s2;

  always @(posedge clk) begin
    toggle_s0 <= reg0[31];
    toggle_s1 <= toggle_s0;
    toggle_s2 <= toggle_s1;
  end

  wire write_pulse = rst_n & (toggle_s1 ^ toggle_s2);

  wire [4:0] cfg_target = reg0[20:16];

  wire threshold_write = write_pulse & (cfg_target == 5'd2);
  wire block_tol_write = write_pulse & (cfg_target == 5'd4);

  assign commit_o = write_pulse;
  assign target_o = cfg_target;
  assign bad_target_o = write_pulse & ~(threshold_write | block_tol_write);

  always @(posedge clk) begin
    if (!rst_n)
      threshold_o <= 16'd64;
    else if (threshold_write)
      threshold_o <= reg1[15:0];
  end

  always @(posedge clk) begin
    if (!rst_n)
      block_tol_o <= 32'd0;
    else if (block_tol_write)
      block_tol_o <= reg1;
  end

  reg search_mode;
  reg estop_hold;
  reg [2:0] estop_flags;
  reg [2:0] confirm;

  assign search_mode_o = search_mode;
  assign estop_hold_o = estop_hold;
  assign estop_en_o = estop_flags[0];
  assign block_en_o = estop_flags[1];
  assign short_confirm_o = estop_flags[2];
  assign confirm_o = confirm;
  assign ctrl_o = {12'd0, confirm, 8'd0, estop_flags, 1'b0, estop_hold, 3'd0, search_mode};

  always @(posedge clk) begin
    if (!rst_n) begin
      search_mode <= 0;
      estop_hold <= 0;
      estop_flags <= 0;
      confirm <= 0;
    end else if (cfg_meas_i) begin
      search_mode <= dt2_i[0];
      estop_hold <= dt2_i[4];
      estop_flags <= dt2_i[8:6];
      confirm <= dt2_i[19:17];
    end
  end

  always @(posedge clk) begin
    if (!rst_n) begin
      start_freq_o <= 0;
      step_o <= 0;
      n_points_o <= 0;
      avg_shift_o <= 0;
    end else if (cfg_sweep_i) begin
      start_freq_o <= dt1_i;
      step_o <= dt2_i;
      n_points_o <= dt3_i[15:0];
      avg_shift_o <= dt4_i[4:0];
    end
  end

  always @(posedge clk) begin
    if (!rst_n) begin
      warmup_shots_o <= 0;
      n_min_o <= 0;
    end else if (cfg_meas_i) begin
      warmup_shots_o <= dt3_i;
      n_min_o <= dt4_i;
    end
  end

  always @(posedge clk) begin
    if (!rst_n) begin
      f_lo_o <= 0;
      f_hi_o <= 32'hFFFFFFFF;
    end else if (cfg_search_i) begin
      f_lo_o <= dt1_i;
      f_hi_o <= dt2_i;
    end
  end

endmodule
