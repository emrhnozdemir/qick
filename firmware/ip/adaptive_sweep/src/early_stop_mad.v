`timescale 1ns / 1ps

module early_stop_mad (
  input wire clk,
  input wire rst_n,

  input wire arm_i,
  input wire en_i,
  input wire fold_i,
  input wire first_i,
  input wire [31:0] n_i,
  input wire [31:0] n_min_i,

  input wire signed [17:0] x_i_i,
  input wire signed [17:0] x_q_i,
  input wire signed [17:0] mean_ep_i_i,
  input wire signed [17:0] mean_ep_q_i,

  input wire thr_wr_en_i,
  input wire [4:0] thr_wr_addr_i,
  input wire [45:0] thr_wr_data_i,

  output wire [4:0] j_o,
  output wire stop_o,
  output wire [45:0] dev_acc_o
);

  reg [45:0] thr_table [0:31];
  integer ti;

  initial begin
    for (ti = 0; ti < 32; ti = ti + 1)
      thr_table[ti] = {46{1'b0}};
  end

  always @(posedge clk) begin
    if (thr_wr_en_i)
      thr_table[thr_wr_addr_i] <= thr_wr_data_i;
  end

  (* mark_debug = "true" *) reg [31:0] epoch_r;
  (* mark_debug = "true" *) reg [4:0] j_r;
  (* mark_debug = "true" *) reg signed [17:0] mean_lat_i;
  (* mark_debug = "true" *) reg signed [17:0] mean_lat_q;
  (* mark_debug = "true" *) reg [45:0] dev_acc;

  assign j_o = j_r;
  assign dev_acc_o = dev_acc;

  wire at_epoch = fold_i & (n_i == epoch_r);

  wire signed [18:0] d_i = {x_i_i[17], x_i_i} - {mean_lat_i[17], mean_lat_i};
  wire signed [18:0] d_q = {x_q_i[17], x_q_i} - {mean_lat_q[17], mean_lat_q};
  wire [18:0] a_i = d_i[18] ? (~d_i + 19'd1) : d_i;
  wire [18:0] a_q = d_q[18] ? (~d_q + 19'd1) : d_q;
  wire [15:0] c_i = (a_i > 19'd65535) ? 16'hFFFF : a_i[15:0];
  wire [15:0] c_q = (a_q > 19'd65535) ? 16'hFFFF : a_q[15:0];
  wire [16:0] dev_term = {1'b0, c_i} + {1'b0, c_q};

  wire dev_en = fold_i & ~first_i;
  wire [45:0] dev_next = dev_en ? (dev_acc + {29'd0, dev_term}) : dev_acc;

  wire [45:0] thr_cur = thr_table[j_r];
  wire stop_ok = (n_min_i != 32'd0) & (epoch_r >= n_min_i);

  assign stop_o = en_i & at_epoch & stop_ok & (dev_next <= thr_cur);

  always @(posedge clk) begin
    if (!rst_n) begin
      epoch_r <= 32'd1;
      j_r <= 5'd0;
      mean_lat_i <= {18{1'b0}};
      mean_lat_q <= {18{1'b0}};
      dev_acc <= {46{1'b0}};
    end else if (arm_i) begin
      epoch_r <= 32'd1;
      j_r <= 5'd0;
      mean_lat_i <= {18{1'b0}};
      mean_lat_q <= {18{1'b0}};
      dev_acc <= {46{1'b0}};
    end else if (fold_i) begin
      dev_acc <= dev_next;
      if (at_epoch) begin
        mean_lat_i <= mean_ep_i_i;
        mean_lat_q <= mean_ep_q_i;
        epoch_r <= epoch_r << 1;
        j_r <= j_r + 5'd1;
      end else begin
        mean_lat_i <= mean_lat_i;
        mean_lat_q <= mean_lat_q;
        epoch_r <= epoch_r;
        j_r <= j_r;
      end
    end else begin
      epoch_r <= epoch_r;
      j_r <= j_r;
      mean_lat_i <= mean_lat_i;
      mean_lat_q <= mean_lat_q;
      dev_acc <= dev_acc;
    end
  end

  (* mark_debug = "true" *) reg arm_dbg;
  (* mark_debug = "true" *) reg en_dbg;
  (* mark_debug = "true" *) reg fold_dbg;
  (* mark_debug = "true" *) reg first_dbg;
  (* mark_debug = "true" *) reg at_epoch_dbg;
  (* mark_debug = "true" *) reg dev_en_dbg;
  (* mark_debug = "true" *) reg [16:0] dev_term_dbg;
  (* mark_debug = "true" *) reg [45:0] dev_next_dbg;
  (* mark_debug = "true" *) reg [45:0] thr_cur_dbg;
  (* mark_debug = "true" *) reg stop_ok_dbg;
  (* mark_debug = "true" *) reg stop_dbg;
  (* mark_debug = "true" *) reg thr_wr_en_dbg;
  (* mark_debug = "true" *) reg [4:0] thr_wr_addr_dbg;
  always @(posedge clk) begin
    if (!rst_n) begin
      arm_dbg <= 1'b0;
      en_dbg <= 1'b0;
      fold_dbg <= 1'b0;
      first_dbg <= 1'b0;
      at_epoch_dbg <= 1'b0;
      dev_en_dbg <= 1'b0;
      dev_term_dbg <= 17'd0;
      dev_next_dbg <= {46{1'b0}};
      thr_cur_dbg <= {46{1'b0}};
      stop_ok_dbg <= 1'b0;
      stop_dbg <= 1'b0;
      thr_wr_en_dbg <= 1'b0;
      thr_wr_addr_dbg <= 5'd0;
    end else begin
      arm_dbg <= arm_i;
      en_dbg <= en_i;
      fold_dbg <= fold_i;
      first_dbg <= first_i;
      at_epoch_dbg <= at_epoch;
      dev_en_dbg <= dev_en;
      dev_term_dbg <= dev_term;
      dev_next_dbg <= dev_next;
      thr_cur_dbg <= thr_cur;
      stop_ok_dbg <= stop_ok;
      stop_dbg <= stop_o;
      thr_wr_en_dbg <= thr_wr_en_i;
      thr_wr_addr_dbg <= thr_wr_addr_i;
    end
  end

endmodule
