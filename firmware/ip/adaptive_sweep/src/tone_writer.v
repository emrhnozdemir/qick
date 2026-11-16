`timescale 1ns / 1ps

module tone_writer(
  input clk,
  input rst_n,

  input start_i,
  input [7:0] mask_i,
  output done_o,

  output [2:0] tone_o,
  input [31:0] freq_i,
  input [31:0] gen_base_i,
  input [36:0] ro_base_i,
  input [34:0] ratio_i,

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
  output m_axi_rready
);

  localparam [2:0] S_IDLE = 3'd0;
  localparam [2:0] S_PICK = 3'd1;
  localparam [2:0] S_GEN = 3'd2;
  localparam [2:0] S_ID = 3'd3;
  localparam [2:0] S_RO = 3'd4;
  localparam [2:0] S_WE_ON = 3'd5;
  localparam [2:0] S_WE_OFF = 3'd6;
  localparam [2:0] S_SETTLE = 3'd7;

  reg [2:0] state, next_state;
  reg [2:0] tone;
  reg [7:0] mask;
  reg [4:0] count;
  reg aw_pending;
  reg w_pending;

  wire picked = (count == 5'd6);
  wire settled = (count == 5'd31);
  wire last_tone = (tone == 3'd7);
  wire written = m_axi_bvalid & ~aw_pending & ~w_pending;

  always @(posedge clk) begin
    if (!rst_n)
      state <= S_IDLE;
    else
      state <= next_state;
  end

  always @(*) begin
    next_state = state;
    case (state)
      S_IDLE: next_state = start_i ? S_PICK : S_IDLE;
      S_PICK: next_state = ~picked ? S_PICK : (mask[tone] ? S_GEN : (last_tone ? S_WE_ON : S_PICK));
      S_GEN: next_state = written ? S_ID : S_GEN;
      S_ID: next_state = written ? S_RO : S_ID;
      S_RO: next_state = written ? (last_tone ? S_WE_ON : S_PICK) : S_RO;
      S_WE_ON: next_state = written ? S_WE_OFF : S_WE_ON;
      S_WE_OFF: next_state = written ? S_SETTLE : S_WE_OFF;
      S_SETTLE: next_state = settled ? S_IDLE : S_SETTLE;
    endcase
  end

  wire skip = (state == S_PICK) & picked & ~mask[tone] & ~last_tone;
  wire advance = skip | ((state == S_RO) & written & ~last_tone);

  always @(posedge clk) begin
    if (!rst_n) begin
      tone <= 0;
      mask <= 0;
      count <= 0;
    end else begin
      case (state)
        S_IDLE: begin
          tone <= 0;
          count <= 0;
          if (start_i)
            mask <= mask_i;
        end
        S_PICK: begin
          if (picked)
            count <= 0;
          else
            count <= count + 5'd1;
          if (advance)
            tone <= tone + 3'd1;
        end
        S_RO: begin
          count <= 0;
          if (advance)
            tone <= tone + 3'd1;
        end
        S_SETTLE: begin
          count <= count + 5'd1;
        end
        default: begin
          count <= 0;
        end
      endcase
    end
  end

  wire next_writing = (next_state == S_GEN) | (next_state == S_ID) | (next_state == S_RO) |
                      (next_state == S_WE_ON) | (next_state == S_WE_OFF);

  always @(posedge clk) begin
    if (!rst_n) begin
      aw_pending <= 0;
      w_pending <= 0;
    end else if (state != next_state) begin
      aw_pending <= next_writing;
      w_pending <= next_writing;
    end else begin
      if (m_axi_awready)
        aw_pending <= 0;
      if (m_axi_wready)
        w_pending <= 0;
    end
  end

  reg signed [31:0] gen_offset;
  reg signed [66:0] product;
  reg signed [66:0] product_d;
  reg [36:0] band;
  reg [31:0] ro_pinc;
  reg [15:0] ro_id;

  wire signed [34:0] ratio = ratio_i;
  wire signed [66:0] rounded = product_d + 67'sd1073741824;
  wire [37:0] centred = {1'b0, band} + 38'd1073741824;
  wire [5:0] channel_steps = centred[36:31];
  wire [5:0] channel = {~channel_steps[5], channel_steps[4:0]};

  always @(posedge clk) begin
    if (!rst_n) begin
      gen_offset <= 0;
      product <= 0;
      product_d <= 0;
      band <= 0;
      ro_pinc <= 0;
      ro_id <= 0;
    end else begin
      gen_offset <= freq_i - gen_base_i;
      product <= gen_offset * ratio;
      product_d <= product;
      band <= ro_base_i + {rounded[62:31], 5'd0};
      ro_pinc <= band[31:0] - {channel_steps[0], 31'd0};
      ro_id <= {5'd0, channel[2:0], 5'd0, channel[5:3]};
    end
  end

  wire to_readout = (state == S_ID) | (state == S_RO);
  wire [6:0] offset = (state == S_GEN) ? {2'd0, tone, 2'd0} :
                      (state == S_ID) ? {2'd0, tone, 2'd0} :
                      (state == S_RO) ? (7'd32 + {1'b0, tone, 3'd0}) :
                      7'd96;

  assign tone_o = tone;
  assign done_o = (state == S_SETTLE) & settled;

  assign m_axi_awaddr = {15'd0, to_readout, 9'd0, offset};
  assign m_axi_awprot = 3'd0;
  assign m_axi_awvalid = aw_pending;
  assign m_axi_wdata = (state == S_GEN) ? freq_i :
                       (state == S_ID) ? {16'd0, ro_id} :
                       (state == S_RO) ? ro_pinc :
                       {31'd0, (state == S_WE_ON)};
  assign m_axi_wstrb = 4'hF;
  assign m_axi_wvalid = w_pending;
  assign m_axi_bready = 1'b1;
  assign m_axi_araddr = 32'd0;
  assign m_axi_arprot = 3'd0;
  assign m_axi_arvalid = 1'b0;
  assign m_axi_rready = 1'b0;

endmodule
