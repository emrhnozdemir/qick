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
  output reg qtag_rdy_o,
  output reg [31:0] qtag_dt1_o,
  output reg [31:0] qtag_dt2_o,
  output reg qtag_vld_o,

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

  // QP2 (qick_peripheral) handshake -- no algorithm wired up yet, so the IP
  // just reports idle/ready. Reconnect qtag_dt1_o/dt2_o/vld_o once the
  // datapath exists.
  always @(posedge clk) begin
    if (!rst_n) begin
      qtag_rdy_o <= 1'b1;
      qtag_dt1_o <= 32'd0;
      qtag_dt2_o <= 32'd0;
      qtag_vld_o <= 1'b0;
    end else begin
      qtag_rdy_o <= qtag_rdy_o;
      qtag_dt1_o <= qtag_dt1_o;
      qtag_dt2_o <= qtag_dt2_o;
      qtag_vld_o <= 1'b0;
    end
  end

  // AXI4-Lite slave: python-facing register file. Placeholder map (see
  // axi_slv.v) -- rename/extend REG0_REG..REG7_REG once the register list
  // for this IP is defined; unused until then.
  wire [31:0] REG0_REG;
  wire [31:0] REG1_REG;
  wire [31:0] REG2_REG;
  wire [31:0] REG3_REG;
  wire [31:0] REG4_REG;
  wire [31:0] REG5_REG;
  wire [31:0] REG6_REG;
  wire [31:0] REG7_REG;

  axi_slv u_axi_slv (
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

endmodule
