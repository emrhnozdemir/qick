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

  (* MARK_DEBUG = "TRUE" *) output reg [31:0] start_freq_o,
  (* MARK_DEBUG = "TRUE" *) output reg [31:0] step_o,
  (* MARK_DEBUG = "TRUE" *) output reg [15:0] n_points_o,
  (* MARK_DEBUG = "TRUE" *) output reg [4:0] avg_shift_o,
  (* MARK_DEBUG = "TRUE" *) output reg [31:0] warmup_shots_o,
  (* MARK_DEBUG = "TRUE" *) output reg [31:0] n_min_o,
  (* MARK_DEBUG = "TRUE" *) output reg [31:0] f_lo_o,
  (* MARK_DEBUG = "TRUE" *) output reg [31:0] f_hi_o,
  (* MARK_DEBUG = "TRUE" *) output reg [15:0] pair_min_o,
  (* MARK_DEBUG = "TRUE" *) output reg [15:0] pair_max_o,
  (* MARK_DEBUG = "TRUE" *) output reg [15:0] threshold_o,

  output search_mode_o,
  output estop_hold_o,
  output estop_en_o,
  output [2:0] confirm_o,

  output step_lut_write_o,
  output [5:0] step_lut_addr_o,
  output [31:0] step_lut_data_o,
  output reg [6:0] step_lut_len_o,

  output offset_lut_write_o,
  output [5:0] offset_lut_addr_o,
  output [31:0] offset_lut_data_o,
  output reg [6:0] offset_lut_len_o
);

  wire [31:0] reg0;
  wire [31:0] reg1;
  wire [31:0] reg2;
  wire [31:0] reg3;
  wire [31:0] reg4;
  wire [31:0] reg5;
  wire [31:0] reg6;
  wire [31:0] reg7;

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
    .REG3_REG(reg3),
    .REG4_REG(reg4),
    .REG5_REG(reg5),
    .REG6_REG(reg6),
    .REG7_REG(reg7)
  );

  (* MARK_DEBUG = "TRUE" *) reg toggle_s0;
  (* MARK_DEBUG = "TRUE" *) reg toggle_s1;
  (* MARK_DEBUG = "TRUE" *) reg toggle_s2;

  always @(posedge clk) begin
    if (!rst_n) begin
      toggle_s0 <= 0;
      toggle_s1 <= 0;
      toggle_s2 <= 0;
    end else begin
      toggle_s0 <= reg0[31];
      toggle_s1 <= toggle_s0;
      toggle_s2 <= toggle_s1;
    end
  end

  (* MARK_DEBUG = "TRUE" *) wire write_pulse = toggle_s1 ^ toggle_s2;

  wire [6:0] cfg_len = reg0[30:24];
  wire [2:0] cfg_last = reg0[23:21];
  wire [4:0] cfg_target = reg0[20:16];
  wire [7:0] cfg_base = reg0[15:8];

  wire lut_commit = write_pulse & ((cfg_target == 5'd0) | (cfg_target == 5'd1));
  wire threshold_write = write_pulse & (cfg_target == 5'd2);
  wire ctrl_write = write_pulse & (cfg_target == 5'd3);

  (* MARK_DEBUG = "TRUE" *) reg burst_active;
  (* MARK_DEBUG = "TRUE" *) reg [2:0] burst_cnt;
  reg burst_sel;
  reg [2:0] burst_last;
  reg [7:0] burst_base;

  always @(posedge clk) begin
    if (!rst_n) begin
      burst_active <= 1'b0;
      burst_cnt <= 3'd0;
      burst_sel <= 1'b0;
      burst_last <= 3'd0;
      burst_base <= 8'd0;
    end else if (lut_commit) begin
      burst_active <= 1'b1;
      burst_cnt <= 3'd0;
      burst_sel <= cfg_target[0];
      burst_last <= cfg_last;
      burst_base <= cfg_base;
    end else if (burst_active & (burst_cnt == burst_last)) begin
      burst_active <= 1'b0;
      burst_cnt <= 3'd0;
      burst_sel <= burst_sel;
      burst_last <= burst_last;
      burst_base <= burst_base;
    end else if (burst_active) begin
      burst_active <= 1'b1;
      burst_cnt <= burst_cnt + 3'd1;
      burst_sel <= burst_sel;
      burst_last <= burst_last;
      burst_base <= burst_base;
    end else begin
      burst_active <= burst_active;
      burst_cnt <= burst_cnt;
      burst_sel <= burst_sel;
      burst_last <= burst_last;
      burst_base <= burst_base;
    end
  end

  reg [31:0] burst_data;

  always @(*) begin
    if (burst_cnt == 3'd0)
      burst_data = reg1;
    else if (burst_cnt == 3'd1)
      burst_data = reg2;
    else if (burst_cnt == 3'd2)
      burst_data = reg3;
    else if (burst_cnt == 3'd3)
      burst_data = reg4;
    else if (burst_cnt == 3'd4)
      burst_data = reg5;
    else if (burst_cnt == 3'd5)
      burst_data = reg6;
    else
      burst_data = reg7;
  end

  wire [7:0] burst_addr = burst_base + {5'd0, burst_cnt};

  assign step_lut_write_o = burst_active & ~burst_sel;
  assign offset_lut_write_o = burst_active & burst_sel;
  assign step_lut_addr_o = burst_addr[5:0];
  assign step_lut_data_o = burst_data;
  assign offset_lut_addr_o = burst_addr[5:0];
  assign offset_lut_data_o = burst_data;

  always @(posedge clk) begin
    if (!rst_n)
      threshold_o <= 16'd64;
    else if (threshold_write)
      threshold_o <= reg1[15:0];
  end

  always @(posedge clk) begin
    if (!rst_n) begin
      step_lut_len_o <= 7'd64;
      offset_lut_len_o <= 7'd64;
    end else begin
      if (lut_commit & (cfg_target == 5'd0) & (cfg_len != 7'd0))
        step_lut_len_o <= cfg_len;
      else
        step_lut_len_o <= step_lut_len_o;

      if (lut_commit & (cfg_target == 5'd1) & (cfg_len != 7'd0))
        offset_lut_len_o <= cfg_len;
      else
        offset_lut_len_o <= offset_lut_len_o;
    end
  end

  (* MARK_DEBUG = "TRUE" *) reg [31:0] ctrl;

  assign search_mode_o = ctrl[0];
  assign estop_hold_o = ctrl[4];
  assign estop_en_o = ctrl[6];
  assign confirm_o = ctrl[19:17];

  always @(posedge clk) begin
    if (!rst_n)
      ctrl <= 0;
    else if (cfg_meas_i)
      ctrl <= dt2_i;
    else if (ctrl_write)
      ctrl <= reg1;
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
      pair_min_o <= 1;
      pair_max_o <= 1;
    end else if (cfg_search_i) begin
      f_lo_o <= dt1_i;
      f_hi_o <= dt2_i;
      pair_min_o <= dt3_i[15:0];
      pair_max_o <= dt4_i[15:0];
    end
  end

endmodule
