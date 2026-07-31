`timescale 1ns / 1ps

// iq_feeder -- testbench-only replay of recorded resonator I/Q.
//
// Replaces the resonator + readout + avg_buffer chain with I/Q that was
// actually measured on hardware, so that the adaptive_sweep IP can be run
// against real resonator data (noise, asymmetry, drift) instead of a model.
//
// One entry of `mem` is one SHOT, in the exact format avg_buffer's m2_axis
// puts on the wire: 64 bits packed {Q[31:0], I[31:0]}, each a signed sum
// over the NSAMP samples of that shot's readout window. The testbench loads
// it with $readmemh through iq_load_mem() (see tb_qick.sv).
//
// Pacing: the feeder is driven by the DUT's own point arming. Every arm_i
// pulse starts a burst of shots_i beats -- exactly the averager_value the
// IP is about to fold into one point -- spaced gap_i clocks apart. That
// keeps the file cursor aligned with the sweep no matter how the sweep
// advances, which a free-running or trigger-counted source would not.
//
// Entries are consumed in file order: entry k is the k-th shot of the run,
// so the file must be generated in the same point/shot order the sweep
// visits. cursor_o exports the read position for logging.

module iq_feeder #(
  parameter DEPTH = 65536
) (
  input wire clk,
  input wire rst_n,

  input wire arm_i,
  input wire [31:0] shots_i,
  input wire [15:0] gap_i,

  output reg m_axis_tvalid,
  output reg [63:0] m_axis_tdata,
  output reg [31:0] cursor_o
);

  reg [63:0] mem [0:DEPTH-1];
  integer i;

  initial begin
    for (i = 0; i < DEPTH; i = i + 1)
      mem[i] = 64'd0;
  end

  reg [31:0] shots_left;
  reg [15:0] gap_cnt;

  wire beat_now = (shots_left != 32'd0) & (gap_cnt == 16'd0);

  always @(posedge clk) begin
    if (!rst_n) begin
      shots_left <= 32'd0;
      gap_cnt <= 16'd0;
      cursor_o <= 32'd0;
      m_axis_tvalid <= 1'b0;
      m_axis_tdata <= 64'd0;
    end else if (arm_i) begin
      // A new point: start its burst. Any leftover of the previous burst is
      // dropped, matching the IP -- arming restarts its shot counter too.
      shots_left <= shots_i;
      gap_cnt <= gap_i;
      cursor_o <= cursor_o;
      m_axis_tvalid <= 1'b0;
      m_axis_tdata <= m_axis_tdata;
    end else if (beat_now) begin
      shots_left <= shots_left - 32'd1;
      gap_cnt <= gap_i;
      cursor_o <= cursor_o + 32'd1;
      m_axis_tvalid <= 1'b1;
      m_axis_tdata <= mem[cursor_o[15:0]];
    end else begin
      shots_left <= shots_left;
      gap_cnt <= (gap_cnt == 16'd0) ? 16'd0 : gap_cnt - 16'd1;
      cursor_o <= cursor_o;
      m_axis_tvalid <= 1'b0;
      m_axis_tdata <= m_axis_tdata;
    end
  end

endmodule
