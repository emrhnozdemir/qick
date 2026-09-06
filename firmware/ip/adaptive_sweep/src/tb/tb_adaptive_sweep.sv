`timescale 1ns / 1ps

module tb_adaptive_sweep;

  localparam NSAMP = 32'd190;
  localparam START_FREQ = 32'h1000_0000;
  localparam STEP = 32'h0010_0000;
  localparam N_POINTS = 32'd5;
  localparam AVG_T0 = 32'd4;
  localparam AVG_THR = 32'd64;
  localparam AVG_T0_SH = 32'd2;
  localparam AVG_THR_SH = 32'd6;

  localparam [31:0] CTRL_SHIFT = 32'h0000_0022;
  localparam [31:0] CTRL_MEAN32 = 32'h0000_0006;
  localparam [31:0] CTRL_SPLIT = 32'h0004_0046;
  localparam [31:0] CTRL_SPLIT_HOLD = 32'h0004_0056;

  reg clk;
  reg s_axi_aclk;
  reg rst_n;

  reg qtag_en_i;
  reg [4:0] qtag_op_i;
  reg [31:0] qtag_dt1_i, qtag_dt2_i, qtag_dt3_i, qtag_dt4_i;
  wire qtag_rdy_o;
  wire [31:0] qtag_dt1_o, qtag_dt2_o;
  wire qtag_vld_o;

  reg s_axis_tvalid;
  wire s_axis_tready;
  reg [63:0] s_axis_tdata;

  reg s_axi_aresetn;
  reg [7:0] s_axi_awaddr;
  reg s_axi_awvalid;
  wire s_axi_awready;
  reg [31:0] s_axi_wdata;
  reg [3:0] s_axi_wstrb;
  reg s_axi_wvalid;
  wire s_axi_wready;
  wire [1:0] s_axi_bresp;
  wire s_axi_bvalid;
  wire [1:0] s_axi_rresp;
  wire s_axi_rvalid;
  wire interrupt_o;
  wire [31:0] s_axi_rdata;
  wire s_axi_arready;

  integer errors;
  integer block_irq_count = 0;
  integer block_irq_before;

  always @(posedge clk) begin
    if (!rst_n) block_irq_count <= 0;
    else if (interrupt_o) block_irq_count <= block_irq_count + 1;
  end

  initial begin
    clk = 1'b0;
    forever #2.5 clk = ~clk;
  end

  initial begin
    s_axi_aclk = 1'b0;
    forever #4.0 s_axi_aclk = ~s_axi_aclk;
  end

  adaptive_sweep dut (
    .clk           (clk),
    .rst_n         (rst_n),
    .qtag_en_i     (qtag_en_i),
    .qtag_op_i     (qtag_op_i),
    .qtag_dt1_i    (qtag_dt1_i),
    .qtag_dt2_i    (qtag_dt2_i),
    .qtag_dt3_i    (qtag_dt3_i),
    .qtag_dt4_i    (qtag_dt4_i),
    .qtag_rdy_o    (qtag_rdy_o),
    .qtag_dt1_o    (qtag_dt1_o),
    .qtag_dt2_o    (qtag_dt2_o),
    .qtag_vld_o    (qtag_vld_o),
    .s_axis_tvalid (s_axis_tvalid),
    .s_axis_tready (s_axis_tready),
    .s_axis_tdata  (s_axis_tdata),
    .s_axi_aclk    (s_axi_aclk),
    .s_axi_aresetn (s_axi_aresetn),
    .s_axi_awaddr  (s_axi_awaddr),
    .s_axi_awprot  (3'd0),
    .s_axi_awvalid (s_axi_awvalid),
    .s_axi_awready (s_axi_awready),
    .s_axi_wdata   (s_axi_wdata),
    .s_axi_wstrb   (s_axi_wstrb),
    .s_axi_wvalid  (s_axi_wvalid),
    .s_axi_wready  (s_axi_wready),
    .s_axi_bresp   (s_axi_bresp),
    .s_axi_bvalid  (s_axi_bvalid),
    .s_axi_bready  (1'b1),
    .s_axi_araddr  (8'd0),
    .s_axi_arprot  (3'd0),
    .s_axi_arvalid (1'b0),
    .s_axi_arready (s_axi_arready),
    .s_axi_rdata   (s_axi_rdata),
    .s_axi_rresp   (s_axi_rresp),
    .s_axi_rvalid  (s_axi_rvalid),
    .s_axi_rready  (1'b1),
    .interrupt_o   (interrupt_o)
  );


  task automatic check32(input string name, input [31:0] got, input [31:0] exp);
    begin
      if (got !== exp) begin
        $display("FAIL %0s: got %0d (0x%08x), expected %0d (0x%08x)", name, got, got, exp, exp);
        errors = errors + 1;
      end else begin
        $display("PASS %0s = %0d (0x%08x)", name, got, got);
      end
    end
  endtask

  task automatic check64(input string name, input [63:0] got, input [63:0] exp);
    begin
      if (got !== exp) begin
        $display("FAIL %0s: got %0d (0x%016x), expected %0d (0x%016x)", name, got, got, exp, exp);
        errors = errors + 1;
      end else begin
        $display("PASS %0s = %0d (0x%016x)", name, got, got);
      end
    end
  endtask

  task automatic qp2_op(input [4:0] op, input [31:0] d1, input [31:0] d2, input [31:0] d3, input [31:0] d4);
    begin
      @(posedge clk);
      qtag_op_i <= op;
      qtag_dt1_i <= d1;
      qtag_dt2_i <= d2;
      qtag_dt3_i <= d3;
      qtag_dt4_i <= d4;
      qtag_en_i <= 1'b1;
      @(posedge clk);
      qtag_en_i <= 1'b0;
      @(posedge clk);
      @(posedge clk);
      @(posedge clk);
    end
  endtask

  task automatic axi_write(input [7:0] addr, input [31:0] data);
    begin
      @(posedge s_axi_aclk);
      s_axi_awaddr <= addr;
      s_axi_wdata <= data;
      s_axi_wstrb <= 4'hF;
      s_axi_awvalid <= 1'b1;
      s_axi_wvalid <= 1'b1;
      do
        @(posedge s_axi_aclk);
      while (!(s_axi_awready && s_axi_wready));
      s_axi_awvalid <= 1'b0;
      s_axi_wvalid <= 1'b0;
      repeat (4) @(posedge s_axi_aclk);
    end
  endtask

  reg axi_tog;

  // REG0 = {[31] toggle, [30:24] len, [23:21] count-1, [20:16] target,
  //         [15:8] addr, [7:0] reserved}; REG1..REG7 = seven payload words.
  task automatic axi_tbl_write(input [4:0] target, input [7:0] addr, input [31:0] data, input [6:0] len);
    begin
      axi_write(8'h04, data);
      axi_write(8'h00, {axi_tog, len, 3'd0, target, addr, 8'd0});
      axi_tog = ~axi_tog;
      axi_write(8'h00, {axi_tog, len, 3'd0, target, addr, 8'd0});
      repeat (10) @(posedge clk);
    end
  endtask

  task automatic axi_lut_burst4(input [4:0] target, input [7:0] addr,
                                input [31:0] d0, input [31:0] d1,
                                input [31:0] d2, input [31:0] d3, input [6:0] len);
    begin
      axi_write(8'h04, d0);
      axi_write(8'h08, d1);
      axi_write(8'h0C, d2);
      axi_write(8'h10, d3);
      axi_write(8'h00, {axi_tog, len, 3'd3, target, addr, 8'd0});
      axi_tog = ~axi_tog;
      axi_write(8'h00, {axi_tog, len, 3'd3, target, addr, 8'd0});
      repeat (10) @(posedge clk);
    end
  endtask

  task automatic axi_estop_thr(input [15:0] d);
    begin
      axi_tbl_write(5'd2, 8'd0, {16'd0, d}, 7'd0);
      repeat (40) @(posedge clk);
    end
  endtask

  integer arm_count;
  integer arm_taken;

  always @(posedge clk) begin
    if (!rst_n)
      arm_count <= 0;
    else if (dut.point_arm)
      arm_count <= arm_count + 1;
    else
      arm_count <= arm_count;
  end

  task automatic wait_arm;
    integer guard;
    begin
      guard = 0;
      while ((arm_count == arm_taken) && (guard < 20000)) begin
        @(posedge clk);
        guard = guard + 1;
      end
      if (guard >= 20000) begin
        $display("FAIL: timed out waiting for an arm");
        errors = errors + 1;
      end
      repeat (6) @(posedge clk);
      arm_taken = arm_count;
    end
  endtask

  task automatic feed_point(input integer nshots, input integer isum, input integer qsum);
    integer n;
    begin
      wait_arm;
      for (n = 0; n < nshots; n = n + 1) begin
        @(posedge clk);
        s_axis_tvalid <= 1'b1;
        s_axis_tdata <= {qsum[31:0], isum[31:0]};
      end
      @(posedge clk);
      s_axis_tvalid <= 1'b0;
    end
  endtask

  task automatic feed_alternating(input integer nshots, input integer lo, input integer hi);
    integer n;
    begin
      wait_arm;
      for (n = 0; n < nshots; n = n + 1) begin
        @(posedge clk);
        s_axis_tvalid <= 1'b1;
        s_axis_tdata <= {32'd0, ((n % 2) == 0) ? lo[31:0] : hi[31:0]};
      end
      @(posedge clk);
      s_axis_tvalid <= 1'b0;
    end
  endtask

  task automatic feed_block_step;
    integer n;
    integer ii, qq;
    begin
      wait_arm;
      for (n = 0; n < 64; n = n + 1) begin
        ii = (n < 4) ? 1000 : 100000;
        qq = (n < 4) ? -500 : -50000;
        @(posedge clk);
        s_axis_tvalid <= 1;
        s_axis_tdata <= {qq[31:0], ii[31:0]};
      end
      @(posedge clk);
      s_axis_tvalid <= 0;
    end
  endtask

  integer grid_valid_cnt;
  integer search_valid_cnt;

  always @(posedge clk) begin
    if (!rst_n) begin
      grid_valid_cnt <= 0;
      search_valid_cnt <= 0;
    end else begin
      if (dut.grid_valid)
        grid_valid_cnt <= grid_valid_cnt + 1;
      else
        grid_valid_cnt <= grid_valid_cnt;

      if (dut.search_valid)
        search_valid_cnt <= search_valid_cnt + 1;
      else
        search_valid_cnt <= search_valid_cnt;
    end
  end

  task automatic run_probes(input integer avg, input integer isum, input integer guardmax);
    integer g;
    begin
      g = 0;
      while (!qtag_rdy_o && (g < guardmax)) begin
        qp2_op(5'd7, 32'd0, 32'd0, 32'd0, 32'd0);
        if (!qtag_rdy_o && qtag_dt2_o[0])
          feed_point(avg, isum, 0);
        else
          g = g;
        g = g + 1;
      end
      if (g >= guardmax) begin
        $display("FAIL: timed out serving GD/KW probes");
        errors = errors + 1;
      end
    end
  endtask

  task automatic run_probes_ab(input integer avg, input integer isum_a, input integer isum_b, input integer guardmax);
    integer g;
    integer k;
    begin
      g = 0;
      k = 0;
      while (!qtag_rdy_o && (g < guardmax)) begin
        qp2_op(5'd7, 32'd0, 32'd0, 32'd0, 32'd0);
        if (!qtag_rdy_o && qtag_dt2_o[0]) begin
          feed_point(avg, ((k % 2) == 0) ? isum_a : isum_b, 0);
          k = k + 1;
        end else begin
          k = k;
        end
        g = g + 1;
      end
      if (g >= guardmax) begin
        $display("FAIL: timed out serving GD/KW probes (ab)");
        errors = errors + 1;
      end else begin
        g = g;
      end
    end
  endtask

  task automatic run_probes_mixed(input integer reverse);
    integer g;
    integer k;
    integer ii;
    begin
      g = 0;
      k = 0;
      while (!qtag_rdy_o && (g < 400)) begin
        qp2_op(5'd7, 32'd0, 32'd0, 32'd0, 32'd0);
        if (!qtag_rdy_o && qtag_dt2_o[0]) begin
          case (k)
            0: ii = reverse ? 30 : 0;
            1: ii = reverse ? 0 : 30;
            2: ii = reverse ? 0 : 10;
            3: ii = reverse ? 10 : 0;
            default: ii = 0;
          endcase
          feed_point(2, ii, 0);
          k = k + 1;
        end
        g = g + 1;
      end
      check32("mixed race served exactly two pairs", k, 32'd4);
      if (g >= 400) begin
        $display("FAIL: timed out serving mixed-sign race");
        errors = errors + 1;
      end
    end
  endtask

  task automatic run_boundary_probes(input integer dip_mode);
    integer g;
    integer k;
    integer distance_from_upper;
    integer ii;
    reg [31:0] upper;
    begin
      upper = START_FREQ + 4 * STEP;
      g = 0;
      k = 0;
      while (!qtag_rdy_o && (g < 400)) begin
        qp2_op(5'd7, 32'd0, 32'd0, 32'd0, 32'd0);
        if (!qtag_rdy_o && qtag_dt2_o[0]) begin
          check32($sformatf("boundary probe %0d frequency", k), qtag_dt1_o,
                  (k == 0) ? (upper - STEP) : upper);
          distance_from_upper = (upper - qtag_dt1_o) / STEP;
          ii = dip_mode ? (100 - distance_from_upper) : (10 * distance_from_upper);
          feed_point(2, ii, 0);
          k = k + 1;
        end
        g = g + 1;
      end
      check32("boundary run served exactly one pair", k, 32'd2);
      if (g >= 400) begin
        $display("FAIL: timed out serving upper-bound probes");
        errors = errors + 1;
      end
    end
  endtask

  task automatic run_range_probes(input string name,
      input [31:0] lo, input [31:0] hi,
      input [31:0] expected_a, input [31:0] expected_b,
      input integer amplitude_a, input integer amplitude_b,
      input [31:0] expected_x);
    integer g;
    integer k;
    begin
      g = 0;
      k = 0;
      while (!qtag_rdy_o && (g < 400)) begin
        qp2_op(5'd7, 32'd0, 32'd0, 32'd0, 32'd0);
        if (!qtag_rdy_o && qtag_dt2_o[0]) begin
          check32($sformatf("%s probe %0d", name, k), qtag_dt1_o,
                  (k == 0) ? expected_a : expected_b);
          check32($sformatf("%s probe %0d stays in range", name, k),
                  {31'd0, (qtag_dt1_o >= lo) && (qtag_dt1_o <= hi)}, 32'd1);
          feed_point(2, (k == 0) ? amplitude_a : amplitude_b, 0);
          k = k + 1;
        end
        g = g + 1;
      end
      check32($sformatf("%s exactly one pair", name), k, 32'd2);
      check32($sformatf("%s result", name), qtag_dt1_o, expected_x);
      check32($sformatf("%s result stays in range", name),
              {31'd0, (qtag_dt1_o >= lo) && (qtag_dt1_o <= hi)}, 32'd1);
      if (g >= 400) begin
        $display("FAIL %s: timed out serving bounded probes", name);
        errors = errors + 1;
      end
    end
  endtask

  task automatic wait_finish;
    integer guard;
    begin
      guard = 0;
      while (!qtag_vld_o && (guard < 20000)) begin
        @(posedge clk);
        guard = guard + 1;
      end
      if (guard >= 20000) begin
        $display("FAIL: timed out waiting for qtag_vld_o");
        errors = errors + 1;
      end
    end
  endtask

  initial begin
    #3000000;
    $display("FAIL: global timeout");
    $finish;
  end

  integer p;
  reg [31:0] amp_of_point [0:4];
  reg [31:0] status_t0;
  reg [31:0] n_used_t1, n_used_t2;
  reg [31:0] status_t1, status_t2;
  integer grid_before, search_before;
  reg [31:0] tl_probes [0:9];
  integer tl_i;
  integer tl_g;

  initial begin
    errors = 0;
    arm_taken = 0;
    axi_tog = 1'b0;
    rst_n = 1'b0;
    s_axi_aresetn = 1'b0;
    qtag_en_i = 1'b0;
    qtag_op_i = 5'd0;
    qtag_dt1_i = 32'd0;
    qtag_dt2_i = 32'd0;
    qtag_dt3_i = 32'd0;
    qtag_dt4_i = 32'd0;
    s_axis_tvalid = 1'b0;
    s_axis_tdata = 64'd0;
    s_axi_awaddr = 8'd0;
    s_axi_awvalid = 1'b0;
    s_axi_wdata = 32'd0;
    s_axi_wstrb = 4'd0;
    s_axi_wvalid = 1'b0;

    amp_of_point[0] = 100 * 128;
    amp_of_point[1] = 200 * 128;
    amp_of_point[2] = 500 * 128;
    amp_of_point[3] = 300 * 128;
    amp_of_point[4] = 150 * 128;

    repeat (20) @(posedge clk);
    rst_n = 1'b1;
    s_axi_aresetn = 1'b1;
    repeat (20) @(posedge clk);

    check32("BC0 block tolerance reset", dut.block_tol, 0);
    check32("BC0 block guard reset disabled", {31'd0, dut.block_en}, 0);

    qp2_op(5'd2, NSAMP, CTRL_SHIFT, 32'd0, 32'd0);
    qp2_op(5'd0, START_FREQ, STEP, N_POINTS, AVG_T0_SH);
    qp2_op(5'd1, 32'd0, 32'd0, 32'd0, 32'd0);

    for (p = 0; p < 5; p = p + 1)
      feed_point(AVG_T0, amp_of_point[p], 0);

    wait_finish;
    check32("T0 peak freq_word", qtag_dt1_o, START_FREQ + 2 * STEP);
    check32("T0 rdy after finish", {31'd0, qtag_rdy_o}, 32'd1);
    check64("T0 peak power", dut.u_peak_finder.best_amplitude, 64'd4096000000);

    // T0c  n_points = 2 exercises last_point on the VERY FIRST advance,
    //      which is the exact boundary of the (next_index == last_index)
    //      test that replaced (point_idx + 2 >= n_pts).  n_points 1 and 5
    //      are covered elsewhere; 2 was the gap.
    qp2_op(5'd2, NSAMP, CTRL_SHIFT, 32'd0, 32'd0);
    qp2_op(5'd0, START_FREQ, STEP, 32'd2, AVG_T0_SH);
    qp2_op(5'd1, 32'd0, 32'd0, 32'd0, 32'd0);
    feed_point(AVG_T0, 32'd100, 0);
    feed_point(AVG_T0, 32'd900, 0);
    wait_finish;
    check32("T0c two-point sweep picks point 1", qtag_dt1_o, START_FREQ + STEP);
    qp2_op(5'd10, 32'd0, 32'd0, 32'd0, 32'd0);
    qp2_op(5'd3, 32'd0, 32'd0, 32'd0, 32'd0);
    check32("T0c point_idx reached 1 (status[31:16], now lossless)",
            {16'd0, qtag_dt1_o[31:16]}, 32'd1);

    // T0z  ALL-ZERO GRID, peak mode. Every point has power 0, so the strict
    //      is_better never fires; the first measurement is taken anyway
    //      (best_valid) and the answer is the first grid frequency, not 0.
    qp2_op(5'd2, NSAMP, CTRL_SHIFT, 32'd0, 32'd0);
    qp2_op(5'd0, START_FREQ, STEP, 32'd3, AVG_T0_SH);
    qp2_op(5'd1, 32'd0, 32'd0, 32'd0, 32'd0);
    feed_point(AVG_T0, 0, 0);
    feed_point(AVG_T0, 0, 0);
    feed_point(AVG_T0, 0, 0);
    wait_finish;
    check32("T0z all-zero grid returns the first frequency", qtag_dt1_o, START_FREQ);
    check64("T0z all-zero grid power", dut.u_peak_finder.best_amplitude, 64'd0);

    // T0t  TIES: three equal points, the first occurrence wins.
    qp2_op(5'd2, NSAMP, CTRL_SHIFT, 32'd0, 32'd0);
    qp2_op(5'd0, START_FREQ, STEP, 32'd3, AVG_T0_SH);
    qp2_op(5'd1, 32'd0, 32'd0, 32'd0, 32'd0);
    feed_point(AVG_T0, 100 * 128, 0);
    feed_point(AVG_T0, 100 * 128, 0);
    feed_point(AVG_T0, 100 * 128, 0);
    wait_finish;
    check32("T0t tie keeps the first frequency", qtag_dt1_o, START_FREQ);

    qp2_op(5'd2, NSAMP, CTRL_SHIFT, 32'd0, 32'd0);
    qp2_op(5'd0, START_FREQ, STEP, N_POINTS, AVG_T0_SH);
    qp2_op(5'd1, 32'd0, 32'd0, 32'd0, 32'd0);
    for (p = 0; p < 5; p = p + 1)
      feed_point(AVG_T0, amp_of_point[p], 0);
    wait_finish;

    qp2_op(5'd7, 32'd0, 32'd0, 32'd0, 32'd0);
    check32("T0 result survives a late OP10", qtag_dt1_o,
            START_FREQ + 2 * STEP);
    qp2_op(5'd3, 32'd0, 32'd0, 32'd0, 32'd0);
    check32("T0 result survives a late OP3", qtag_dt1_o,
            START_FREQ + 2 * STEP);
    qp2_op(5'd4, 32'd0, 32'd0, 32'd0, 32'd0);
    check32("T0 result survives a late OP5", qtag_dt1_o,
            START_FREQ + 2 * STEP);
    qp2_op(5'd8, 32'd0, 32'd0, 32'd0, 32'd0);
    check32("T0 result survives a late OP11", qtag_dt1_o,
            START_FREQ + 2 * STEP);

    qp2_op(5'd10, 32'd0, 32'd0, 32'd0, 32'd0);
    check32("T0 vld cleared by OP13", {31'd0, qtag_vld_o}, 32'd0);

    qp2_op(5'd3, 32'd0, 32'd0, 32'd0, 32'd0);
    status_t0 = qtag_dt1_o;
    check32("T0 status point_idx", {16'd0, status_t0[31:16]}, 32'd4);
    check32("T0 status estop_en", {31'd0, status_t0[10]}, 32'd0);
    check32("T0 status dest", {31'd0, status_t0[11]}, 32'd0);
    check32("T0 status busy", {31'd0, status_t0[2]}, 32'd0);
    check32("T0 status finish_seen", {31'd0, status_t0[1]}, 32'd1);
    check32("T0 status freq_at_max", qtag_dt2_o, START_FREQ + 2 * STEP);

    qp2_op(5'd2, NSAMP, CTRL_SPLIT, 32'd0, 32'd8);
    qp2_op(5'd0, START_FREQ, STEP, 32'd1, AVG_THR_SH);
    qp2_op(5'd1, 32'd0, 32'd0, 32'd0, 32'd0);

    feed_alternating(AVG_THR, 100 * 128, 102 * 128);
    wait_finish;

    qp2_op(5'd10, 32'd0, 32'd0, 32'd0, 32'd0);
    qp2_op(5'd4, 32'd0, 32'd0, 32'd0, 32'd0);
    n_used_t1 = qtag_dt1_o;
    qp2_op(5'd3, 32'd0, 32'd0, 32'd0, 32'd0);
    status_t1 = qtag_dt1_o;
    check32("T1 n_used (reset default D=64)", n_used_t1, 32'd8);
    check32("T1 early_stop (reset default D=64)", {31'd0, status_t1[8]}, 32'd1);
    check32("T1 estop_en", {31'd0, status_t1[10]}, 32'd1);

    axi_estop_thr(16'd101);

    qp2_op(5'd2, NSAMP, CTRL_SPLIT, 32'd0, 32'd8);
    qp2_op(5'd0, START_FREQ, STEP, 32'd1, AVG_THR_SH);
    qp2_op(5'd1, 32'd0, 32'd0, 32'd0, 32'd0);

    feed_alternating(AVG_THR, 100 * 128, 102 * 128);
    wait_finish;

    qp2_op(5'd10, 32'd0, 32'd0, 32'd0, 32'd0);
    qp2_op(5'd4, 32'd0, 32'd0, 32'd0, 32'd0);
    n_used_t2 = qtag_dt1_o;
    qp2_op(5'd3, 32'd0, 32'd0, 32'd0, 32'd0);
    status_t2 = qtag_dt1_o;
    check32("T2 n_used (D=101, boundary pass)", n_used_t2, 32'd8);
    check32("T2 early_stop (D=101, boundary pass)", {31'd0, status_t2[8]}, 32'd1);
    qp2_op(5'd11, 32'd0, 32'd0, 32'd0, 32'd0);
    check32("T2 mean I at stop", qtag_dt1_o, 32'd12928);
    check32("T2 mean Q at stop", qtag_dt2_o, 32'd0);

    qp2_op(5'd10, 32'd0, 32'd0, 32'd0, 32'd0);
    qp2_op(5'd4, 32'd0, 32'd0, 32'd0, 32'd0);
    check32("T2 diag converged", {31'd0, qtag_dt2_o[8]}, 32'd1);
    check32("T2 diag k (stop at 2^3)", {27'd0, qtag_dt2_o[7:3]}, 32'd3);
    check32("T2 diag type (0 = converged)", {29'd0, qtag_dt2_o[2:0]}, 32'd0);
    check32("T2 diag nconv_count", {16'd0, qtag_dt2_o[31:16]}, 32'd0);

    axi_estop_thr(16'd102);

    qp2_op(5'd2, NSAMP, CTRL_SPLIT, 32'd0, 32'd8);
    qp2_op(5'd0, START_FREQ, STEP, 32'd1, AVG_THR_SH);
    qp2_op(5'd1, 32'd0, 32'd0, 32'd0, 32'd0);

    feed_alternating(AVG_THR, 100 * 128, 102 * 128);
    wait_finish;

    qp2_op(5'd10, 32'd0, 32'd0, 32'd0, 32'd0);
    qp2_op(5'd4, 32'd0, 32'd0, 32'd0, 32'd0);
    check32("T2b n_used (D=102, boundary fail)", qtag_dt1_o, AVG_THR);
    qp2_op(5'd3, 32'd0, 32'd0, 32'd0, 32'd0);
    check32("T2b early_stop (D=102, boundary fail)", {31'd0, qtag_dt1_o[8]}, 32'd0);

    qp2_op(5'd10, 32'd0, 32'd0, 32'd0, 32'd0);
    qp2_op(5'd4, 32'd0, 32'd0, 32'd0, 32'd0);
    check32("T2b diag converged (capped, so 0)", {31'd0, qtag_dt2_o[8]}, 32'd0);
    check32("T2b diag type (4 = ran to the cap)", {29'd0, qtag_dt2_o[2:0]}, 32'd4);
    check32("T2b diag nconv_count", {16'd0, qtag_dt2_o[31:16]}, 32'd1);

    axi_estop_thr(16'd102);
    qp2_op(5'd10, 32'd0, 32'd0, 32'd0, 32'd0);
    qp2_op(5'd2, NSAMP, CTRL_SPLIT, 32'd0, 32'd8);
    qp2_op(5'd0, START_FREQ, STEP, 32'd2, AVG_THR_SH);
    qp2_op(5'd1, 32'd0, 32'd0, 32'd0, 32'd0);

    feed_alternating(AVG_THR, 100 * 128, 102 * 128);
    feed_point(AVG_THR, 1000, 500);
    wait_finish;

    // The IP keeps no per-point history: OP4 always describes the point that
    // retired last, and the interrupt handler is what files it under a grid
    // index.  Point 0 here runs to the cap, point 1 converges at 8, so the
    // verdict is point 1's and nconv_count has counted point 0.
    qp2_op(5'd10, 32'd0, 32'd0, 32'd0, 32'd0);
    qp2_op(5'd4, 32'd0, 32'd0, 32'd0, 32'd0);
    check32("TDIAG n_used of the last point", qtag_dt1_o, 32'd8);
    check32("TDIAG last point converged", {31'd0, qtag_dt2_o[8]}, 32'd1);
    check32("TDIAG last point k (stop at 2^3)", {27'd0, qtag_dt2_o[7:3]}, 32'd3);
    check32("TDIAG last point type (0 = converged)", {29'd0, qtag_dt2_o[2:0]}, 32'd0);
    check32("TDIAG nconv_count (point 0 ran to the cap)", {16'd0, qtag_dt2_o[31:16]}, 32'd1);

    axi_estop_thr(16'd96);

    qp2_op(5'd2, NSAMP, CTRL_MEAN32, 32'd0, 32'd0);
    qp2_op(5'd0, START_FREQ, STEP, 32'd1, 32'd0);
    qp2_op(5'd1, 32'd0, 32'd0, 32'd0, 32'd0);

    feed_point(1, 32'h7FFF_FFFF, 32'h8000_0000);

    wait_finish;
    check32("T3 rail peak freq_word", qtag_dt1_o, START_FREQ);
    check64("T3 int32 rail power", dut.u_peak_finder.best_amplitude, 64'h7FFF_FFFF_0000_0001);
    qp2_op(5'd10, 32'd0, 32'd0, 32'd0, 32'd0);
    qp2_op(5'd3, 32'd0, 32'd0, 32'd0, 32'd0);

    qp2_op(5'd10, 32'd0, 32'd0, 32'd0, 32'd0);
    qp2_op(5'd2, NSAMP, CTRL_SHIFT, 32'd0, 32'd0);
    qp2_op(5'd0, START_FREQ, STEP, N_POINTS, 32'd1);
    qp2_op(5'd9, 32'd0, 32'hFFFF_FFFF, 32'd1, 32'd2);

    grid_before = grid_valid_cnt;
    search_before = search_valid_cnt;

    qp2_op(5'd5, START_FREQ, 32'h0002_0000, 32'd0, 32'd4);
    run_probes(2, 100 * 128, 400);

    check32("T5 gd result x", qtag_dt1_o, START_FREQ);
    check32("T5 gd converged word", qtag_dt2_o, 32'h0002_0001);
    check32("T5 grid path stayed idle", grid_valid_cnt - grid_before, 32'd0);
    check32("T5 search path saw every probe", search_valid_cnt - search_before, 32'd8);

    qp2_op(5'd10, 32'd0, 32'd0, 32'd0, 32'd0);
    qp2_op(5'd3, 32'd0, 32'd0, 32'd0, 32'd0);
    check32("T5 status dest", {31'd0, qtag_dt1_o[11]}, 32'd1);

    // TR1  RACING MODE MOVES. lambda 1, m_min 1, m_max 2, patience 0,
    //      max_iter 3. Probe B (x + step) is served louder than probe A (x),
    //      so every pair certifies on its own (|dp| > |dp| >> 1) and x steps
    //      up by cfg_step each iteration: 3 iterations, 6 probes, capped.
    qp2_op(5'd10, 32'd0, 32'd0, 32'd0, 32'd0);
    qp2_op(5'd2, NSAMP, CTRL_SHIFT, 32'd0, 32'd0);
    qp2_op(5'd0, START_FREQ, STEP, N_POINTS, 32'd1);
    qp2_op(5'd9, 32'd0, 32'hFFFF_FFFF, 32'd1, 32'd2);
    search_before = search_valid_cnt;
    qp2_op(5'd5, START_FREQ, 32'h0000_0010, 32'd0, 32'd3);
    run_probes_ab(2, 100 * 128, 200 * 128, 400);
    check32("TR1 racing gd moved +3 steps", qtag_dt1_o, START_FREQ + 3 * STEP);
    check32("TR1 racing gd done word (capped, iter 3)", qtag_dt2_o, 32'h0003_0002);
    check32("TR1 racing gd served 6 probes", search_valid_cnt - search_before, 32'd6);

    qp2_op(5'd10, 32'd0, 32'd0, 32'd0, 32'd0);
    qp2_op(5'd9, 32'd0, 32'hFFFF_FFFF, 32'd2, 32'd2);
    qp2_op(5'd5, START_FREQ, 32'h0000_0010, 32'd0, 32'd1);
    run_probes_mixed(0);
    check32("TR2 racing follows positive accumulated sign", qtag_dt1_o, START_FREQ + STEP);
    check32("TR2 one iteration capped", qtag_dt2_o, 32'h0001_0002);

    qp2_op(5'd10, 32'd0, 32'd0, 32'd0, 32'd0);
    qp2_op(5'd5, START_FREQ, 32'h0000_0010, 32'd0, 32'd1);
    run_probes_mixed(1);
    check32("TR3 racing follows negative accumulated sign", qtag_dt1_o, START_FREQ - STEP);

    qp2_op(5'd10, 32'd0, 32'd0, 32'd0, 32'd0);
    qp2_op(5'd2, NSAMP, CTRL_SHIFT | 32'd1, 32'd0, 32'd0);
    qp2_op(5'd6, START_FREQ, 32'h0000_0010, 32'd0, 32'd1);
    run_probes_mixed(0);
    check32("TR4 KW dip follows accumulated sign", qtag_dt1_o, START_FREQ - STEP);
    qp2_op(5'd2, NSAMP, CTRL_SHIFT, 32'd0, 32'd0);
    qp2_op(5'd9, 32'd0, 32'hFFFF_FFFF, 32'd1, 32'd2);

    // TR0  lambda 0 IS DEGENERATE. Same response, lambda 0: |sum(dp)| can
    //      never exceed sum(|dp|), so no pair count certifies; every
    //      iteration exhausts m_max = 2 and ties, and x never leaves x0.
    //      This is the case plan_sweep rejects (lambda_ >= 1 in racing mode).
    qp2_op(5'd10, 32'd0, 32'd0, 32'd0, 32'd0);
    search_before = search_valid_cnt;
    qp2_op(5'd5, START_FREQ, 32'h0000_0000, 32'd0, 32'd3);
    run_probes_ab(2, 100 * 128, 200 * 128, 400);
    check32("TR0 lambda 0 never moves", qtag_dt1_o, START_FREQ);
    check32("TR0 lambda 0 done word (capped, iter 3)", qtag_dt2_o, 32'h0003_0002);
    check32("TR0 lambda 0 served 12 probes", search_valid_cnt - search_before, 32'd12);

    qp2_op(5'd10, 32'd0, 32'd0, 32'd0, 32'd0);
    qp2_op(5'd2, NSAMP, CTRL_SPLIT, 32'd0, 32'd8);
    qp2_op(5'd0, START_FREQ, STEP, 32'd1, 32'd6);
    qp2_op(5'd1, 32'd0, 32'd0, 32'd0, 32'd0);

    feed_point(64, 1000, 500);
    wait_finish;

    check32("T6 split freq", qtag_dt1_o, START_FREQ);
    check64("T6 split power", dut.u_peak_finder.best_amplitude, 64'd1250000);
    qp2_op(5'd10, 32'd0, 32'd0, 32'd0, 32'd0);
    qp2_op(5'd4, 32'd0, 32'd0, 32'd0, 32'd0);
    check32("T6 n_used", qtag_dt1_o, 32'd8);
    check32("T6 diag word", qtag_dt2_o, 32'h0000_0118);
    qp2_op(5'd3, 32'd0, 32'd0, 32'd0, 32'd0);
    check32("T6 status early_stop", {31'd0, qtag_dt1_o[8]}, 32'd1);
    qp2_op(5'd11, 32'd0, 32'd0, 32'd0, 32'd0);
    check32("T6 mean I", qtag_dt1_o, 32'd1000);
    check32("T6 mean Q", qtag_dt2_o, 32'd500);

    qp2_op(5'd2, NSAMP, CTRL_SPLIT_HOLD, 32'd0, 32'd8);
    qp2_op(5'd0, START_FREQ, STEP, 32'd1, 32'd6);
    qp2_op(5'd1, 32'd0, 32'd0, 32'd0, 32'd0);

    feed_point(64, 1000, 500);
    wait_finish;

    check64("T6b drain power", dut.u_peak_finder.best_amplitude, 64'd1250000);
    qp2_op(5'd10, 32'd0, 32'd0, 32'd0, 32'd0);
    qp2_op(5'd4, 32'd0, 32'd0, 32'd0, 32'd0);
    check32("T6b n_used", qtag_dt1_o, 32'd8);
    check32("T6b diag word", qtag_dt2_o, 32'h0000_0118);

    qp2_op(5'd2, NSAMP, CTRL_SPLIT, 32'd0, 32'd4);
    qp2_op(5'd0, START_FREQ, STEP, 32'd1, 32'd7);
    qp2_op(5'd1, 32'd0, 32'd0, 32'd0, 32'd0);

    feed_alternating(128, 128000, 64000);
    wait_finish;

    check64("T9 cap power", dut.u_peak_finder.best_amplitude, 64'd9216000000);
    qp2_op(5'd10, 32'd0, 32'd0, 32'd0, 32'd0);
    qp2_op(5'd4, 32'd0, 32'd0, 32'd0, 32'd0);
    check32("T9 n_used", qtag_dt1_o, 32'd128);
    check32("T9 diag word", qtag_dt2_o, 32'h0001_0204);
    qp2_op(5'd3, 32'd0, 32'd0, 32'd0, 32'd0);
    check32("T9 status early_stop", {31'd0, qtag_dt1_o[8]}, 32'd0);
    qp2_op(5'd11, 32'd0, 32'd0, 32'd0, 32'd0);
    check32("T9 mean I", qtag_dt1_o, 32'd96000);
    check32("T9 mean Q", qtag_dt2_o, 32'd0);

    // one commit each, four entries per burst - the TL1 probe checks below
    // are what verifies the burst engine wrote them to the right addresses
    axi_lut_burst4(5'd0, 8'd0, 32'd64, 32'd32, 32'd8, 32'd2, 7'd4);
    axi_lut_burst4(5'd1, 8'd0, 32'd100, 32'd50, 32'd20, 32'd10, 7'd4);

    qp2_op(5'd2, NSAMP, CTRL_SHIFT, 32'd0, 32'd0);
    qp2_op(5'd0, START_FREQ, STEP, N_POINTS, 32'd1);
    qp2_op(5'd9, 32'd0, 32'hFFFF_FFFF, 32'd1, 32'd1);

    tl_probes[0] = 32'd268435356;
    tl_probes[1] = 32'd268435556;
    tl_probes[2] = 32'd268435470;
    tl_probes[3] = 32'd268435570;
    tl_probes[4] = 32'd268435532;
    tl_probes[5] = 32'd268435572;
    tl_probes[6] = 32'd268435550;
    tl_probes[7] = 32'd268435570;
    tl_probes[8] = 32'd268435552;
    tl_probes[9] = 32'd268435572;

    grid_before = grid_valid_cnt;
    search_before = search_valid_cnt;

    qp2_op(5'd6, 32'h1000_0000, 32'h0003_0001, 32'd16, 32'd10);

    tl_i = 0;
    tl_g = 0;
    while (!qtag_rdy_o && (tl_g < 400)) begin
      qp2_op(5'd7, 32'd0, 32'd0, 32'd0, 32'd0);
      if (!qtag_rdy_o && qtag_dt2_o[0]) begin
        if (tl_i < 10) begin
          check32($sformatf("TL1 probe %0d freq", tl_i), qtag_dt1_o, tl_probes[tl_i]);
        end else begin
          $display("FAIL TL1: more than 10 probes");
          errors = errors + 1;
        end
        feed_point(2, ((tl_i % 2) == 0) ? 100 * 128 : 200 * 128, 0);
        tl_i = tl_i + 1;
      end else begin
        tl_i = tl_i;
      end
      tl_g = tl_g + 1;
    end
    if (tl_g >= 400) begin
      $display("FAIL TL1: timed out serving schedule-mode probes");
      errors = errors + 1;
    end else begin
      tl_g = tl_g;
    end

    check32("TL1 probes served", tl_i, 32'd10);
    check32("TL1 kw result x", qtag_dt1_o, 32'h1000_006C);
    check32("TL1 kw done word", qtag_dt2_o, 32'h0005_0001);
    check32("TL1 grid path stayed idle", grid_valid_cnt - grid_before, 32'd0);
    check32("TL1 search path saw every probe", search_valid_cnt - search_before, 32'd10);

    qp2_op(5'd10, 32'd0, 32'd0, 32'd0, 32'd0);
    qp2_op(5'd2, NSAMP, CTRL_SHIFT, 32'd0, 32'd0);
    qp2_op(5'd0, START_FREQ, STEP, 32'd0, 32'd1);
    qp2_op(5'd9, START_FREQ, START_FREQ + 4 * STEP, 32'd1, 32'd1);
    qp2_op(5'd5, START_FREQ + 4 * STEP, 32'h0001_0010, 32'd0, 32'd1);
    run_boundary_probes(0);
    check32("TB1 GD peak moves inward from upper bound", qtag_dt1_o, START_FREQ + 3 * STEP);
    check32("TB1 GD avoids false tie convergence", qtag_dt2_o, 32'h0001_0002);

    qp2_op(5'd10, 32'd0, 32'd0, 32'd0, 32'd0);
    qp2_op(5'd2, NSAMP, CTRL_SHIFT | 32'd1, 32'd0, 32'd0);
    qp2_op(5'd5, START_FREQ + 4 * STEP, 32'h0001_0010, 32'd0, 32'd1);
    run_boundary_probes(1);
    check32("TB2 GD dip moves inward from upper bound", qtag_dt1_o, START_FREQ + 3 * STEP);
    check32("TB2 GD dip avoids false tie convergence", qtag_dt2_o, 32'h0001_0002);

    qp2_op(5'd10, 32'd0, 32'd0, 32'd0, 32'd0);
    qp2_op(5'd2, NSAMP, CTRL_SHIFT, 32'd0, 32'd0);
    qp2_op(5'd5, START_FREQ + 4 * STEP, 32'h0001_0011, 32'd0, 32'd1);
    run_boundary_probes(0);
    check32("TB3 scheduled GD moves by LUT step at upper bound", qtag_dt1_o, START_FREQ + 4 * STEP - 32'd64);

    qp2_op(5'd10, 32'd0, 32'd0, 32'd0, 32'd0);
    qp2_op(5'd6, START_FREQ + 4 * STEP, 32'h0001_0010, 32'd0, 32'd1);
    run_boundary_probes(0);
    check32("TB4 KW upper-bound behavior unchanged", qtag_dt1_o, START_FREQ + 3 * STEP);

    qp2_op(5'd10, 32'd0, 32'd0, 32'd0, 32'd0);
    qp2_op(5'd0, 32'd100, 32'd5, 32'd0, 32'd1);
    qp2_op(5'd9, 32'd100, 32'd120, 32'd1, 32'd1);
    qp2_op(5'd5, 32'd80, 32'h0001_0010, 32'd0, 32'd1);
    run_range_probes("BR1 GD below-range seed", 100, 120, 100, 105, 100, 100, 100);

    qp2_op(5'd10, 32'd0, 32'd0, 32'd0, 32'd0);
    qp2_op(5'd6, 32'd140, 32'h0001_0010, 32'd0, 32'd1);
    run_range_probes("BR2 KW above-range seed", 100, 120, 115, 120, 100, 100, 120);

    qp2_op(5'd10, 32'd0, 32'd0, 32'd0, 32'd0);
    qp2_op(5'd0, 32'h8000_0000, 32'd16, 32'd0, 32'd1);
    qp2_op(5'd9, 32'h8000_0000, 32'h8000_0020, 32'd1, 32'd1);
    qp2_op(5'd5, 32'hffff_ffff, 32'h0001_0010, 32'd0, 32'd1);
    run_range_probes("BR3 GD unsigned upper seed", 32'h8000_0000, 32'h8000_0020,
                     32'h8000_0010, 32'h8000_0020, 100, 100, 32'h8000_0020);

    qp2_op(5'd10, 32'd0, 32'd0, 32'd0, 32'd0);
    qp2_op(5'd0, 32'h8000_0000, 32'hffff_ffff, 32'd0, 32'd1);
    qp2_op(5'd6, 32'h7fff_fff0, 32'h0001_0010, 32'd0, 32'd1);
    run_range_probes("BR4 KW unsigned lower seed", 32'h8000_0000, 32'h8000_0020,
                     32'h8000_0000, 32'h8000_0020, 100, 100, 32'h8000_0000);

    qp2_op(5'd10, 32'd0, 32'd0, 32'd0, 32'd0);
    qp2_op(5'd9, 32'hffff_fff0, 32'hffff_ffff, 32'd1, 32'd1);
    qp2_op(5'd5, 32'hffff_fff8, 32'h0000_0010, 32'd0, 32'd1);
    run_range_probes("BR5 positive step cannot wrap", 32'hffff_fff0, 32'hffff_ffff,
                     32'hffff_fff8, 32'hffff_ffff, 100, 200, 32'hffff_ffff);

    qp2_op(5'd10, 32'd0, 32'd0, 32'd0, 32'd0);
    qp2_op(5'd9, 32'd0, 32'd32, 32'd1, 32'd1);
    qp2_op(5'd6, 32'd16, 32'h0000_0010, 32'd0, 32'd1);
    run_range_probes("BR6 negative step cannot wrap", 0, 32, 0, 32, 200, 100, 0);

    qp2_op(5'd10, 32'd0, 32'd0, 32'd0, 32'd0);
    axi_tbl_write(5'd0, 7'd0, 32'hffff_ffff, 7'd1);
    axi_tbl_write(5'd1, 7'd0, 32'hffff_ffff, 7'd1);
    qp2_op(5'd9, 32'h8000_0000, 32'h8000_0020, 32'd1, 32'd1);
    qp2_op(5'd6, 32'h8000_0010, 32'h0000_0011, 32'd0, 32'd1);
    run_range_probes("BR7 scheduled LUT step clamps", 32'h8000_0000, 32'h8000_0020,
                     32'h8000_0000, 32'h8000_0020, 100, 200, 32'h8000_0020);

    qp2_op(5'd10, 32'd0, 32'd0, 32'd0, 32'd0);
    qp2_op(5'd9, 32'h9000_0000, 32'h9000_0000, 32'd1, 32'd1);
    qp2_op(5'd6, 32'hffff_ffff, 32'h0001_0010, 32'd0, 32'd1);
    run_range_probes("BR8 singleton range retains bound", 32'h9000_0000, 32'h9000_0000,
                     32'h9000_0000, 32'h9000_0000, 100, 100, 32'h9000_0000);

    status_t0 = {16'd0, dut.threshold};
    axi_tbl_write(5'd4, 0, 32'hffff_ffff, 0);
    check32("BC1 AXI target4 retains unsigned32 tolerance", dut.block_tol, 32'hffff_ffff);
    check32("BC1 target4 leaves relative threshold unchanged", {16'd0, dut.threshold}, status_t0);
    axi_tbl_write(5'd4, 0, 0, 0);
    qp2_op(5'd2, NSAMP, 32'h0002_00c6, 0, 4);
    check32("BC1 CTRL bit7 enables block guard", {31'd0, dut.block_en}, 1);
    qp2_op(5'd14, 0, 0, 0, 0);
    qp2_op(5'd0, START_FREQ, STEP, 1, 6);
    block_irq_before = block_irq_count;
    qp2_op(5'd1, 0, 0, 0, 0);
    feed_point(64, 1000, -500);
    wait_finish;
    check32("BC1 stable block stops at8", dut.ac_n_used, 8);
    check32("BC1 emits one actual accelerator interrupt", block_irq_count - block_irq_before, 1);
    check32("BC1 retains stable signed mean Q", dut.ac_mean_q, -500);

    qp2_op(5'd2, NSAMP, 32'h0002_00c6, 0, 4);
    qp2_op(5'd14, 0, 0, 0, 0);
    qp2_op(5'd0, START_FREQ, STEP, 1, 6);
    block_irq_before = block_irq_count;
    qp2_op(5'd1, 0, 0, 0, 0);
    feed_block_step;
    wait_finish;
    check32("BC2 step drift runs tocap", dut.ac_n_used, 64);
    check32("BC2 rejected block emits no interrupt", block_irq_count - block_irq_before, 0);
    check32("BC2 cap mean I", dut.ac_mean_i, 93812);

    qp2_op(5'd2, NSAMP, 32'h0002_0046, 0, 4);
    qp2_op(5'd14, 0, 0, 0, 0);
    qp2_op(5'd0, START_FREQ, STEP, 1, 6);
    block_irq_before = block_irq_count;
    qp2_op(5'd1, 0, 0, 0, 0);
    feed_block_step;
    wait_finish;
    check32("BC3 clearing bit7 restores checkpoint4", dut.ac_n_used, 4);
    check32("BC3 legacy emits one interrupt", block_irq_count - block_irq_before, 1);
    check32("BC3 legacy retains first-four mean", dut.ac_mean_i, 1000);

    if (errors == 0)
      $display("ALL TESTS PASSED");
    else
      $fatal(1, "%0d FAILURE(S)", errors);

    $finish;
  end

endmodule
