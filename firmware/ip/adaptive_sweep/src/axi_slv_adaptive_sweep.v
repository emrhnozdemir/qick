`timescale 1ns / 1ps

module axi_slv_adaptive_sweep(
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

  output [31:0] REG0_REG,
  output [31:0] REG1_REG,
  output [31:0] REG2_REG,
  input [31:0] REG3_IN,
  input [31:0] REG4_IN,
  input [31:0] REG5_IN,
  input [31:0] REG6_IN
);

  reg awready;
  reg bvalid;
  reg aw_en;
  reg [2:0] waddr;

  reg arready;
  reg rvalid;
  reg [2:0] raddr;
  reg [31:0] rdata;

  reg toggle;
  reg [4:0] target;
  reg [31:0] payload;
  reg [3:0] read_sel;

  wire aw_take = ~awready & s_axi_awvalid & s_axi_wvalid & aw_en;
  wire wren = awready & s_axi_awvalid & s_axi_wvalid;
  wire ar_take = ~arready & s_axi_arvalid & ~rvalid;
  wire rden = arready & s_axi_arvalid & ~rvalid;

  assign s_axi_awready = awready;
  assign s_axi_wready = awready;
  assign s_axi_bresp = 2'b00;
  assign s_axi_bvalid = bvalid;
  assign s_axi_arready = arready;
  assign s_axi_rdata = rdata;
  assign s_axi_rresp = 2'b00;
  assign s_axi_rvalid = rvalid;

  assign REG0_REG = {toggle, 10'd0, target, 16'd0};
  assign REG1_REG = payload;
  assign REG2_REG = {28'd0, read_sel};

  always @(posedge s_axi_aclk) begin
    if (!s_axi_aresetn) begin
      awready <= 0;
      aw_en <= 1;
      waddr <= 0;
    end else if (aw_take) begin
      awready <= 1;
      aw_en <= 0;
      waddr <= s_axi_awaddr[4:2];
    end else begin
      awready <= 0;
      if (s_axi_bready & bvalid)
        aw_en <= 1;
    end
  end

  always @(posedge s_axi_aclk) begin
    if (!s_axi_aresetn)
      bvalid <= 0;
    else if (wren & ~bvalid)
      bvalid <= 1;
    else if (s_axi_bready & bvalid)
      bvalid <= 0;
  end

  always @(posedge s_axi_aclk) begin
    if (!s_axi_aresetn) begin
      toggle <= 0;
      target <= 0;
      payload <= 0;
      read_sel <= 0;
    end else if (wren) begin
      case (waddr)
        3'd0: begin
          if (s_axi_wstrb[3]) toggle <= s_axi_wdata[31];
          if (s_axi_wstrb[2]) target <= s_axi_wdata[20:16];
        end
        3'd1: begin
          if (s_axi_wstrb[0]) payload[7:0] <= s_axi_wdata[7:0];
          if (s_axi_wstrb[1]) payload[15:8] <= s_axi_wdata[15:8];
          if (s_axi_wstrb[2]) payload[23:16] <= s_axi_wdata[23:16];
          if (s_axi_wstrb[3]) payload[31:24] <= s_axi_wdata[31:24];
        end
        3'd2: begin
          if (s_axi_wstrb[0]) read_sel <= s_axi_wdata[3:0];
        end
      endcase
    end
  end

  always @(posedge s_axi_aclk) begin
    if (!s_axi_aresetn) begin
      arready <= 0;
      raddr <= 0;
    end else if (ar_take) begin
      arready <= 1;
      raddr <= s_axi_araddr[4:2];
    end else begin
      arready <= 0;
    end
  end

  always @(posedge s_axi_aclk) begin
    if (!s_axi_aresetn)
      rvalid <= 0;
    else if (rden)
      rvalid <= 1;
    else if (rvalid & s_axi_rready)
      rvalid <= 0;
  end

  always @(posedge s_axi_aclk) begin
    if (!s_axi_aresetn)
      rdata <= 0;
    else if (rden)
      case (raddr)
        3'd0: rdata <= REG0_REG;
        3'd3: rdata <= REG3_IN;
        3'd4: rdata <= REG4_IN;
        3'd5: rdata <= REG5_IN;
        3'd6: rdata <= REG6_IN;
        default: rdata <= 32'd0;
      endcase
  end

endmodule
