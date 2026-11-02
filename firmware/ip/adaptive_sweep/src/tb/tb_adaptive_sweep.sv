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

  // KW search: the line (one half-width KW_GAM = 0x8_0000 words), the coarse grid the engine
  // walks first (KW_GRID + i * KW_STEP, KW_NPTS points), and the window of the x0 start
  localparam [31:0] KW_F0 = 32'h1002_5000;
  localparam [31:0] KW_GAM = 32'h0008_0000;
  localparam [31:0] KW_GRID = 32'h0FF0_0000;
  localparam [31:0] KW_STEP = 32'h0020_0000;
  localparam [31:0] KW_NPTS = 32'd5;
  localparam [31:0] KW_LO = 32'h0F00_0000;
  localparam [31:0] KW_HI = 32'h1100_0000;
  localparam [31:0] KW_MIN = 32'h0000_2000;

  localparam [4:0] OP_CFG_WINDOW = 5'd0, OP_CFG_ACQ = 5'd1, OP_CFG_GDKW = 5'd2,
                   OP_START = 5'd8, OP_RUN_KW = 5'd9,
                   OP_CLR_RESULT = 5'd10, OP_REARM = 5'd11,
                   OP_GET_FREQ = 5'd16, OP_GET_STATUS = 5'd17,
                   OP_GET_DIAG = 5'd18, OP_GET_MEAN = 5'd19;

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
  reg [7:0] s_axi_araddr;
  reg s_axi_arvalid;
  wire [31:0] c_debug_do;
  wire [31:0] c_data_do;
  wire [31:0] ps_debug_do;

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
    .s_axi_araddr  (s_axi_araddr),
    .s_axi_arprot  (3'd0),
    .s_axi_arvalid (s_axi_arvalid),
    .s_axi_arready (s_axi_arready),
    .s_axi_rdata   (s_axi_rdata),
    .s_axi_rresp   (s_axi_rresp),
    .s_axi_rvalid  (s_axi_rvalid),
    .s_axi_rready  (1'b1),
    .interrupt_o   (interrupt_o),
    .c_debug_do    (c_debug_do),
    .c_data_do     (c_data_do),
    .ps_debug_do   (ps_debug_do)
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

  integer op_calls = 0;
  integer op_pulses = 0;

  always @(posedge clk) begin
    if (rst_n && c_debug_do[31])
      op_pulses <= op_pulses + 1;
  end

  task automatic qp2_op(input [4:0] op, input [31:0] d1, input [31:0] d2, input [31:0] d3, input [31:0] d4);
    begin
      op_calls = op_calls + 1;
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

  task automatic axi_read(input [7:0] addr, output [31:0] data);
    begin
      @(posedge s_axi_aclk);
      s_axi_araddr <= addr;
      s_axi_arvalid <= 1'b1;
      do
        @(posedge s_axi_aclk);
      while (!s_axi_arready);
      s_axi_arvalid <= 1'b0;
      do
        @(posedge s_axi_aclk);
      while (!s_axi_rvalid);
      data = s_axi_rdata;
      repeat (2) @(posedge s_axi_aclk);
    end
  endtask

  // REG2 is the debug read select, a level: write it, let it cross into clk
  // and the selected view cross back into s_axi_aclk.
  task automatic axi_select_view(input [4:0] sel);
    begin
      axi_write(8'h08, {27'd0, sel});
      repeat (10) @(posedge clk);
    end
  endtask

  reg axi_tog;

  // REG0 = {[31] toggle, [30:21] reserved, [20:16] target, [15:0] reserved};
  // REG1 = the payload word.
  task automatic axi_tbl_write(input [4:0] target, input [31:0] data);
    begin
      axi_write(8'h04, data);
      axi_write(8'h00, {axi_tog, 10'd0, target, 16'd0});
      axi_tog = ~axi_tog;
      axi_write(8'h00, {axi_tog, 10'd0, target, 16'd0});
      repeat (10) @(posedge clk);
    end
  endtask

  task automatic axi_estop_thr(input [15:0] d);
    begin
      axi_tbl_write(5'd2, {16'd0, d});
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

  // Shot value of the KW line at drive word f: a Lorentzian of height a on baseline b
  // (b - height for a dip), in exact integer arithmetic so the reference reproduces it.
  function automatic integer kw_line(input [31:0] f, input integer a, input integer b, input bit dip);
    longint d, g2, lor;
    begin
      d = longint'({32'd0, f}) - longint'({32'd0, KW_F0});
      g2 = longint'({32'd0, KW_GAM}) * longint'({32'd0, KW_GAM});
      lor = (longint'(a) * g2) / (g2 + d * d);
      kw_line = dip ? (b - lor) : (b + lor);
    end
  endfunction

  integer kw_probes;
  integer kw_out_of_window;
  reg [31:0] kw_sum, kw_xor;
  reg [31:0] kw_lo_b = KW_GRID, kw_hi_b = KW_GRID + 4 * KW_STEP;

  // The tProcessor side of a KW run: poll GET_FREQ, and for every pending probe feed `shots`
  // shots of I = kw_line(f), Q = 0 (so the power is exactly kw_line(f)^2), with an optional
  // REARM first as the early-stop program does. Records the probe count, the sum and xor of the
  // probe words, and any probe outside [kw_lo_b, kw_hi_b] (the coarse grid's span, or the window).
  task automatic run_kw_line(input integer a, input integer b, input bit dip, input integer shots,
                             input integer rearm);
    integer g;
    begin
      g = 0;
      kw_probes = 0;
      kw_out_of_window = 0;
      kw_sum = 32'd0;
      kw_xor = 32'd0;
      while (!qtag_rdy_o && (g < 20000)) begin
        qp2_op(OP_GET_FREQ, 32'd0, 32'd0, 32'd0, 32'd0);
        if (!qtag_rdy_o && qtag_dt2_o[0]) begin
          if ((qtag_dt1_o < kw_lo_b) || (qtag_dt1_o > kw_hi_b))
            kw_out_of_window = kw_out_of_window + 1;
          kw_probes = kw_probes + 1;
          kw_sum = kw_sum + qtag_dt1_o;
          kw_xor = kw_xor ^ qtag_dt1_o;
          if (rearm)
            qp2_op(OP_REARM, 0, 0, 0, 0);
          feed_point(shots, kw_line(qtag_dt1_o, a, b, dip), 0);
        end
        g = g + 1;
      end
      if (g >= 20000) begin
        $display("FAIL: timed out serving KW probes");
        errors = errors + 1;
      end
    end
  endtask

  // The expected values come from gradient_engine_reference.py run on the same line.
  task automatic check_kw(input string name, input [31:0] x, input [31:0] word, input integer probes,
                          input [31:0] sum, input [31:0] xr);
    begin
      check32({name, " result"}, qtag_dt1_o, x);
      check32({name, " response word"}, qtag_dt2_o, word);
      check32({name, " probes"}, kw_probes, probes);
      check32({name, " probe word sum"}, kw_sum, sum);
      check32({name, " probe word xor"}, kw_xor, xr);
      check32({name, " probes inside the window"}, kw_out_of_window, 0);
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
    #20000000;
    $display("FAIL: global timeout");
    $finish;
  end

  integer p;
  reg [31:0] amp_of_point [0:4];
  reg [31:0] status_t0;
  reg [31:0] axi_rd;
  reg [31:0] commit_before;
  reg [31:0] n_used_t1, n_used_t2;
  reg [31:0] status_t1, status_t2;
  integer grid_before, search_before;

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
    s_axi_araddr = 8'd0;
    s_axi_arvalid = 1'b0;

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

    qp2_op(OP_CFG_ACQ, NSAMP, CTRL_SHIFT, 32'd0, 32'd0);
    qp2_op(OP_CFG_WINDOW, START_FREQ, STEP, N_POINTS, AVG_T0_SH);
    qp2_op(OP_START, 32'd0, 32'd0, 32'd0, 32'd0);

    for (p = 0; p < 5; p = p + 1)
      feed_point(AVG_T0, amp_of_point[p], 0);

    wait_finish;
    check32("T0 peak freq_word", qtag_dt1_o, START_FREQ + 2 * STEP);
    check32("T0 rdy after finish", {31'd0, qtag_rdy_o}, 32'd1);
    check64("T0 peak power", dut.u_peak_finder.tracker.best_amplitude, 64'd4096000000);

    // T0c  n_points = 2 exercises last_point on the VERY FIRST advance,
    //      which is the exact boundary of the (next_index == last_index)
    //      test that replaced (point_idx + 2 >= n_pts).  n_points 1 and 5
    //      are covered elsewhere; 2 was the gap.
    qp2_op(OP_CFG_ACQ, NSAMP, CTRL_SHIFT, 32'd0, 32'd0);
    qp2_op(OP_CFG_WINDOW, START_FREQ, STEP, 32'd2, AVG_T0_SH);
    qp2_op(OP_START, 32'd0, 32'd0, 32'd0, 32'd0);
    feed_point(AVG_T0, 32'd100, 0);
    feed_point(AVG_T0, 32'd900, 0);
    wait_finish;
    check32("T0c two-point sweep picks point 1", qtag_dt1_o, START_FREQ + STEP);
    qp2_op(OP_CLR_RESULT, 32'd0, 32'd0, 32'd0, 32'd0);
    qp2_op(OP_GET_STATUS, 32'd0, 32'd0, 32'd0, 32'd0);
    check32("T0c point_idx reached 1 (status[31:16], now lossless)",
            {16'd0, qtag_dt1_o[31:16]}, 32'd1);

    // T0z  ALL-ZERO GRID, peak mode. Every point has power 0, so the strict
    //      is_better never fires; the first measurement is taken anyway
    //      (best_valid) and the answer is the first grid frequency, not 0.
    qp2_op(OP_CFG_ACQ, NSAMP, CTRL_SHIFT, 32'd0, 32'd0);
    qp2_op(OP_CFG_WINDOW, START_FREQ, STEP, 32'd3, AVG_T0_SH);
    qp2_op(OP_START, 32'd0, 32'd0, 32'd0, 32'd0);
    feed_point(AVG_T0, 0, 0);
    feed_point(AVG_T0, 0, 0);
    feed_point(AVG_T0, 0, 0);
    wait_finish;
    check32("T0z all-zero grid returns the first frequency", qtag_dt1_o, START_FREQ);
    check64("T0z all-zero grid power", dut.u_peak_finder.tracker.best_amplitude, 64'd0);

    // T0t  TIES: three equal points, the first occurrence wins.
    qp2_op(OP_CFG_ACQ, NSAMP, CTRL_SHIFT, 32'd0, 32'd0);
    qp2_op(OP_CFG_WINDOW, START_FREQ, STEP, 32'd3, AVG_T0_SH);
    qp2_op(OP_START, 32'd0, 32'd0, 32'd0, 32'd0);
    feed_point(AVG_T0, 100 * 128, 0);
    feed_point(AVG_T0, 100 * 128, 0);
    feed_point(AVG_T0, 100 * 128, 0);
    wait_finish;
    check32("T0t tie keeps the first frequency", qtag_dt1_o, START_FREQ);

    qp2_op(OP_CFG_ACQ, NSAMP, CTRL_SHIFT, 32'd0, 32'd0);
    qp2_op(OP_CFG_WINDOW, START_FREQ, STEP, N_POINTS, AVG_T0_SH);
    qp2_op(OP_START, 32'd0, 32'd0, 32'd0, 32'd0);
    for (p = 0; p < 5; p = p + 1)
      feed_point(AVG_T0, amp_of_point[p], 0);
    wait_finish;

    qp2_op(OP_GET_FREQ, 32'd0, 32'd0, 32'd0, 32'd0);
    check32("T0 result survives a late GET_FREQ", qtag_dt1_o,
            START_FREQ + 2 * STEP);
    qp2_op(OP_GET_STATUS, 32'd0, 32'd0, 32'd0, 32'd0);
    check32("T0 result survives a late GET_STATUS", qtag_dt1_o,
            START_FREQ + 2 * STEP);
    qp2_op(OP_GET_DIAG, 32'd0, 32'd0, 32'd0, 32'd0);
    check32("T0 result survives a late GET_DIAG", qtag_dt1_o,
            START_FREQ + 2 * STEP);
    qp2_op(OP_GET_MEAN, 32'd0, 32'd0, 32'd0, 32'd0);
    check32("T0 result survives a late GET_MEAN", qtag_dt1_o,
            START_FREQ + 2 * STEP);

    qp2_op(OP_CLR_RESULT, 32'd0, 32'd0, 32'd0, 32'd0);
    check32("T0 vld cleared by CLR_RESULT", {31'd0, qtag_vld_o}, 32'd0);

    qp2_op(OP_GET_STATUS, 32'd0, 32'd0, 32'd0, 32'd0);
    status_t0 = qtag_dt1_o;
    check32("T0 status point_idx", {16'd0, status_t0[31:16]}, 32'd4);
    check32("T0 status estop_en", {31'd0, status_t0[10]}, 32'd0);
    check32("T0 status dest", {31'd0, status_t0[11]}, 32'd0);
    check32("T0 status busy", {31'd0, status_t0[2]}, 32'd0);
    check32("T0 status finish_seen", {31'd0, status_t0[1]}, 32'd1);
    check32("T0 status freq_at_max", qtag_dt2_o, START_FREQ + 2 * STEP);

    qp2_op(OP_CFG_ACQ, NSAMP, CTRL_SPLIT, 32'd0, 32'd8);
    qp2_op(OP_CFG_WINDOW, START_FREQ, STEP, 32'd1, AVG_THR_SH);
    qp2_op(OP_START, 32'd0, 32'd0, 32'd0, 32'd0);

    feed_alternating(AVG_THR, 100 * 128, 102 * 128);
    wait_finish;

    qp2_op(OP_CLR_RESULT, 32'd0, 32'd0, 32'd0, 32'd0);
    qp2_op(OP_GET_DIAG, 32'd0, 32'd0, 32'd0, 32'd0);
    n_used_t1 = qtag_dt1_o;
    qp2_op(OP_GET_STATUS, 32'd0, 32'd0, 32'd0, 32'd0);
    status_t1 = qtag_dt1_o;
    check32("T1 n_used (reset default D=64)", n_used_t1, 32'd8);
    check32("T1 early_stop (reset default D=64)", {31'd0, status_t1[8]}, 32'd1);
    check32("T1 estop_en", {31'd0, status_t1[10]}, 32'd1);

    axi_estop_thr(16'd101);

    qp2_op(OP_CFG_ACQ, NSAMP, CTRL_SPLIT, 32'd0, 32'd8);
    qp2_op(OP_CFG_WINDOW, START_FREQ, STEP, 32'd1, AVG_THR_SH);
    qp2_op(OP_START, 32'd0, 32'd0, 32'd0, 32'd0);

    feed_alternating(AVG_THR, 100 * 128, 102 * 128);
    wait_finish;

    qp2_op(OP_CLR_RESULT, 32'd0, 32'd0, 32'd0, 32'd0);
    qp2_op(OP_GET_DIAG, 32'd0, 32'd0, 32'd0, 32'd0);
    n_used_t2 = qtag_dt1_o;
    qp2_op(OP_GET_STATUS, 32'd0, 32'd0, 32'd0, 32'd0);
    status_t2 = qtag_dt1_o;
    check32("T2 n_used (D=101, boundary pass)", n_used_t2, 32'd8);
    check32("T2 early_stop (D=101, boundary pass)", {31'd0, status_t2[8]}, 32'd1);
    qp2_op(OP_GET_MEAN, 32'd0, 32'd0, 32'd0, 32'd0);
    check32("T2 mean I at stop", qtag_dt1_o, 32'd12928);
    check32("T2 mean Q at stop", qtag_dt2_o, 32'd0);

    qp2_op(OP_CLR_RESULT, 32'd0, 32'd0, 32'd0, 32'd0);
    qp2_op(OP_GET_DIAG, 32'd0, 32'd0, 32'd0, 32'd0);
    check32("T2 diag converged", {31'd0, qtag_dt2_o[8]}, 32'd1);
    check32("T2 diag k (stop at 2^3)", {27'd0, qtag_dt2_o[7:3]}, 32'd3);
    check32("T2 diag type (0 = converged)", {29'd0, qtag_dt2_o[2:0]}, 32'd0);
    check32("T2 diag nconv_count", {16'd0, qtag_dt2_o[31:16]}, 32'd0);

    axi_estop_thr(16'd102);

    qp2_op(OP_CFG_ACQ, NSAMP, CTRL_SPLIT, 32'd0, 32'd8);
    qp2_op(OP_CFG_WINDOW, START_FREQ, STEP, 32'd1, AVG_THR_SH);
    qp2_op(OP_START, 32'd0, 32'd0, 32'd0, 32'd0);

    feed_alternating(AVG_THR, 100 * 128, 102 * 128);
    wait_finish;

    qp2_op(OP_CLR_RESULT, 32'd0, 32'd0, 32'd0, 32'd0);
    qp2_op(OP_GET_DIAG, 32'd0, 32'd0, 32'd0, 32'd0);
    check32("T2b n_used (D=102, boundary fail)", qtag_dt1_o, AVG_THR);
    qp2_op(OP_GET_STATUS, 32'd0, 32'd0, 32'd0, 32'd0);
    check32("T2b early_stop (D=102, boundary fail)", {31'd0, qtag_dt1_o[8]}, 32'd0);

    qp2_op(OP_CLR_RESULT, 32'd0, 32'd0, 32'd0, 32'd0);
    qp2_op(OP_GET_DIAG, 32'd0, 32'd0, 32'd0, 32'd0);
    check32("T2b diag converged (capped, so 0)", {31'd0, qtag_dt2_o[8]}, 32'd0);
    check32("T2b diag type (4 = ran to the cap)", {29'd0, qtag_dt2_o[2:0]}, 32'd4);
    check32("T2b diag nconv_count", {16'd0, qtag_dt2_o[31:16]}, 32'd1);

    axi_estop_thr(16'd102);
    qp2_op(OP_CLR_RESULT, 32'd0, 32'd0, 32'd0, 32'd0);
    qp2_op(OP_CFG_ACQ, NSAMP, CTRL_SPLIT, 32'd0, 32'd8);
    qp2_op(OP_CFG_WINDOW, START_FREQ, STEP, 32'd2, AVG_THR_SH);
    qp2_op(OP_START, 32'd0, 32'd0, 32'd0, 32'd0);

    feed_alternating(AVG_THR, 100 * 128, 102 * 128);
    feed_point(AVG_THR, 1000, 500);
    wait_finish;

    // The IP keeps no per-point history: OP4 always describes the point that
    // retired last, and the interrupt handler is what files it under a grid
    // index.  Point 0 here runs to the cap, point 1 converges at 8, so the
    // verdict is point 1's and nconv_count has counted point 0.
    qp2_op(OP_CLR_RESULT, 32'd0, 32'd0, 32'd0, 32'd0);
    qp2_op(OP_GET_DIAG, 32'd0, 32'd0, 32'd0, 32'd0);
    check32("TDIAG n_used of the last point", qtag_dt1_o, 32'd8);
    check32("TDIAG last point converged", {31'd0, qtag_dt2_o[8]}, 32'd1);
    check32("TDIAG last point k (stop at 2^3)", {27'd0, qtag_dt2_o[7:3]}, 32'd3);
    check32("TDIAG last point type (0 = converged)", {29'd0, qtag_dt2_o[2:0]}, 32'd0);
    check32("TDIAG nconv_count (point 0 ran to the cap)", {16'd0, qtag_dt2_o[31:16]}, 32'd1);

    axi_estop_thr(16'd96);

    qp2_op(OP_CFG_ACQ, NSAMP, CTRL_MEAN32, 32'd0, 32'd0);
    qp2_op(OP_CFG_WINDOW, START_FREQ, STEP, 32'd1, 32'd0);
    qp2_op(OP_START, 32'd0, 32'd0, 32'd0, 32'd0);

    feed_point(1, 32'h7FFF_FFFF, 32'h8000_0000);

    wait_finish;
    check32("T3 rail peak freq_word", qtag_dt1_o, START_FREQ);
    check64("T3 int32 rail power", dut.u_peak_finder.tracker.best_amplitude, 64'h7FFF_FFFF_0000_0001);
    qp2_op(OP_CLR_RESULT, 32'd0, 32'd0, 32'd0, 32'd0);
    qp2_op(OP_GET_STATUS, 32'd0, 32'd0, 32'd0, 32'd0);

    qp2_op(OP_CLR_RESULT, 32'd0, 32'd0, 32'd0, 32'd0);
    qp2_op(OP_CFG_ACQ, NSAMP, CTRL_SHIFT, 32'd0, 32'd0);
    // KW SEARCH (ABI 4, the border search). Every probe's shots carry I = kw_line(f), Q = 0, so the
    // IP's power is exactly kw_line(f)^2 and each run must reproduce gradient_engine_reference.py
    // measurement for measurement: result, response word {iter, nothing_seen, capped, converged},
    // probe count (coarse grid included), and the sum and xor of every probe word. The engine walks
    // the CFG_WINDOW grid, then searches inside the border around its best point; min_step KW_MIN,
    // early-stop threshold 64.
    axi_estop_thr(16'd64);
    qp2_op(OP_CFG_WINDOW, KW_GRID, KW_STEP, KW_NPTS, 32'd1);
    qp2_op(OP_CFG_GDKW, KW_LO, KW_HI, 32'd0, 32'd0);

    grid_before = grid_valid_cnt;
    search_before = search_valid_cnt;
    qp2_op(OP_RUN_KW, 32'd0, 32'd0, KW_MIN, 32'd100);
    run_kw_line(60000, 1000, 0, 2, 0);
    check_kw("K1 peak between grid points", 32'h1001_8a80, 32'h000b_0001, 16, 32'h0101_1653, 32'h1ff8_140b);
    check32("K1 grid path stayed idle", grid_valid_cnt - grid_before, 32'd0);
    check32("K1 search path saw every probe", search_valid_cnt - search_before, 32'd16);
    qp2_op(OP_CLR_RESULT, 32'd0, 32'd0, 32'd0, 32'd0);
    qp2_op(OP_GET_STATUS, 32'd0, 32'd0, 32'd0, 32'd0);
    check32("K1 status dest", {31'd0, qtag_dt1_o[11]}, 32'd1);
    check32("K1 status converged", {31'd0, qtag_dt1_o[13]}, 32'd1);
    check32("K1 status nothing_seen clear", {31'd0, qtag_dt1_o[0]}, 32'd0);

    qp2_op(OP_CLR_RESULT, 32'd0, 32'd0, 32'd0, 32'd0);
    qp2_op(OP_CFG_ACQ, NSAMP, CTRL_SHIFT | 32'd1, 32'd0, 32'd0);
    qp2_op(OP_RUN_KW, 32'd0, 32'd0, KW_MIN, 32'd100);
    run_kw_line(40000, 50000, 1, 2, 0);
    check_kw("K2 dip", 32'h1001_8a80, 32'h000d_0001, 18, 32'h2106_0e53, 32'h1ff8_ec0b);
    qp2_op(OP_CFG_ACQ, NSAMP, CTRL_SHIFT, 32'd0, 32'd0);

    qp2_op(OP_CLR_RESULT, 32'd0, 32'd0, 32'd0, 32'd0);
    qp2_op(OP_RUN_KW, 32'd0, 32'd0, KW_MIN, 32'd2);
    run_kw_line(60000, 1000, 0, 2, 0);
    check_kw("K4 max_iter 2 caps", 32'h1001_8000, 32'h0002_0002, 7, 32'h70fd_8000, 32'h0ffd_8000);

    // n_points < 2: the engine starts from f_lo, x0, f_hi instead of a grid
    kw_lo_b = KW_LO;
    kw_hi_b = KW_HI;
    qp2_op(OP_CFG_WINDOW, KW_GRID, KW_STEP, 32'd0, 32'd1);
    qp2_op(OP_CLR_RESULT, 32'd0, 32'd0, 32'd0, 32'd0);
    qp2_op(OP_RUN_KW, KW_F0 + 3 * KW_GAM, 32'd0, KW_MIN, 32'd100);
    run_kw_line(60000, 1000, 0, 2, 0);
    check_kw("K5 start from f_lo, x0, f_hi", 32'h1002_ff03, 32'h000d_0001, 16, 32'hfff5_f844, 32'h01be_ba0e);

    qp2_op(OP_CFG_WINDOW, KW_GRID, KW_STEP, 32'd1, 32'd1);
    qp2_op(OP_CLR_RESULT, 32'd0, 32'd0, 32'd0, 32'd0);
    qp2_op(OP_RUN_KW, KW_HI - KW_GAM, 32'd0, KW_MIN, 32'd100);
    run_kw_line(60000, 1000, 0, 2, 0);
    check_kw("K9 line outside the three start points", 32'h10f8_0000, 32'h0000_0004, 3, 32'h30f8_0000, 32'h0ef8_0000);
    kw_lo_b = KW_GRID;
    kw_hi_b = KW_GRID + 4 * KW_STEP;
    qp2_op(OP_CFG_WINDOW, KW_GRID, KW_STEP, KW_NPTS, 32'd1);

    // AXI target 5 (the KW patience until ABI 3) is free: a write is a bad target
    axi_tbl_write(5'd5, 32'd4);
    axi_select_view(5'd0);
    axi_read(8'h14, axi_rd);
    check32("K6 target 5 is a bad target", {31'd0, axi_rd[3]}, 32'd1);

    // the threshold register sets the seen gate 8 * pmax / 2^flog2(D): at D = 2 the line can
    // never clear it, so the run ends nothing-seen after the grid
    axi_estop_thr(16'd2);
    qp2_op(OP_CLR_RESULT, 32'd0, 32'd0, 32'd0, 32'd0);
    qp2_op(OP_RUN_KW, 32'd0, 32'd0, KW_MIN, 32'd100);
    run_kw_line(60000, 1000, 0, 2, 0);
    check_kw("K7 threshold 2 hides the line", 32'h1010_0000, 32'h0000_0004, 5, 32'h50f0_0000, 32'h0ff0_0000);
    axi_estop_thr(16'd64);

    qp2_op(OP_CLR_RESULT, 32'd0, 32'd0, 32'd0, 32'd0);
    qp2_op(OP_CFG_ACQ, NSAMP, CTRL_SPLIT, 32'd0, 32'd8);
    qp2_op(OP_CFG_WINDOW, START_FREQ, STEP, 32'd1, 32'd6);
    qp2_op(OP_START, 32'd0, 32'd0, 32'd0, 32'd0);

    feed_point(64, 1000, 500);
    wait_finish;

    check32("T6 split freq", qtag_dt1_o, START_FREQ);
    check64("T6 split power", dut.u_peak_finder.tracker.best_amplitude, 64'd1250000);
    qp2_op(OP_CLR_RESULT, 32'd0, 32'd0, 32'd0, 32'd0);
    qp2_op(OP_GET_DIAG, 32'd0, 32'd0, 32'd0, 32'd0);
    check32("T6 n_used", qtag_dt1_o, 32'd8);
    check32("T6 diag word", qtag_dt2_o, 32'h0000_0118);
    qp2_op(OP_GET_STATUS, 32'd0, 32'd0, 32'd0, 32'd0);
    check32("T6 status early_stop", {31'd0, qtag_dt1_o[8]}, 32'd1);
    qp2_op(OP_GET_MEAN, 32'd0, 32'd0, 32'd0, 32'd0);
    check32("T6 mean I", qtag_dt1_o, 32'd1000);
    check32("T6 mean Q", qtag_dt2_o, 32'd500);

    qp2_op(OP_CFG_ACQ, NSAMP, CTRL_SPLIT_HOLD, 32'd0, 32'd8);
    qp2_op(OP_CFG_WINDOW, START_FREQ, STEP, 32'd1, 32'd6);
    qp2_op(OP_START, 32'd0, 32'd0, 32'd0, 32'd0);

    feed_point(64, 1000, 500);
    wait_finish;

    check64("T6b drain power", dut.u_peak_finder.tracker.best_amplitude, 64'd1250000);
    qp2_op(OP_CLR_RESULT, 32'd0, 32'd0, 32'd0, 32'd0);
    qp2_op(OP_GET_DIAG, 32'd0, 32'd0, 32'd0, 32'd0);
    check32("T6b n_used", qtag_dt1_o, 32'd8);
    check32("T6b diag word", qtag_dt2_o, 32'h0000_0118);

    qp2_op(OP_CFG_ACQ, NSAMP, CTRL_SPLIT, 32'd0, 32'd4);
    qp2_op(OP_CFG_WINDOW, START_FREQ, STEP, 32'd1, 32'd7);
    qp2_op(OP_START, 32'd0, 32'd0, 32'd0, 32'd0);

    feed_alternating(128, 128000, 64000);
    wait_finish;

    check64("T9 cap power", dut.u_peak_finder.tracker.best_amplitude, 64'd9216000000);
    qp2_op(OP_CLR_RESULT, 32'd0, 32'd0, 32'd0, 32'd0);
    qp2_op(OP_GET_DIAG, 32'd0, 32'd0, 32'd0, 32'd0);
    check32("T9 n_used", qtag_dt1_o, 32'd128);
    check32("T9 diag word", qtag_dt2_o, 32'h0001_0204);
    qp2_op(OP_GET_STATUS, 32'd0, 32'd0, 32'd0, 32'd0);
    check32("T9 status early_stop", {31'd0, qtag_dt1_o[8]}, 32'd0);
    qp2_op(OP_GET_MEAN, 32'd0, 32'd0, 32'd0, 32'd0);
    check32("T9 mean I", qtag_dt1_o, 32'd96000);
    check32("T9 mean Q", qtag_dt2_o, 32'd0);

    status_t0 = {16'd0, dut.threshold};
    axi_tbl_write(5'd4, 32'hffff_ffff);
    check32("BC1 AXI target4 retains unsigned32 tolerance", dut.block_tol, 32'hffff_ffff);
    check32("BC1 target4 leaves relative threshold unchanged", {16'd0, dut.threshold}, status_t0);
    axi_tbl_write(5'd4, 0);
    qp2_op(OP_CFG_ACQ, NSAMP, 32'h0002_00c6, 0, 4);
    check32("BC1 CTRL bit7 enables block guard", {31'd0, dut.block_en}, 1);
    qp2_op(OP_REARM, 0, 0, 0, 0);
    qp2_op(OP_CFG_WINDOW, START_FREQ, STEP, 1, 6);
    block_irq_before = block_irq_count;
    qp2_op(OP_START, 0, 0, 0, 0);
    feed_point(64, 1000, -500);
    wait_finish;
    check32("BC1 stable block stops at8", dut.ac_n_used, 8);
    check32("BC1 emits one actual accelerator interrupt", block_irq_count - block_irq_before, 1);
    check32("BC1 retains stable signed mean Q", dut.ac_mean_q, -500);

    qp2_op(OP_CFG_ACQ, NSAMP, 32'h0002_00c6, 0, 4);
    qp2_op(OP_REARM, 0, 0, 0, 0);
    qp2_op(OP_CFG_WINDOW, START_FREQ, STEP, 1, 6);
    block_irq_before = block_irq_count;
    qp2_op(OP_START, 0, 0, 0, 0);
    feed_block_step;
    wait_finish;
    check32("BC2 step drift runs tocap", dut.ac_n_used, 64);
    check32("BC2 rejected block emits no interrupt", block_irq_count - block_irq_before, 0);
    check32("BC2 cap mean I", dut.ac_mean_i, 93812);

    qp2_op(OP_CFG_ACQ, NSAMP, 32'h0002_0046, 0, 4);
    qp2_op(OP_REARM, 0, 0, 0, 0);
    qp2_op(OP_CFG_WINDOW, START_FREQ, STEP, 1, 6);
    block_irq_before = block_irq_count;
    qp2_op(OP_START, 0, 0, 0, 0);
    feed_block_step;
    wait_finish;
    check32("BC3 clearing bit7 restores checkpoint4", dut.ac_n_used, 4);
    check32("BC3 legacy emits one interrupt", block_irq_count - block_irq_before, 1);
    check32("BC3 legacy retains first-four mean", dut.ac_mean_i, 1000);

    // CTRL[8] selects short confirmation through the actual QP register
    // path. Three passes at 4/6/8 retain the first-four sample estimate,
    // even while later paired samples have a very different mean.
    qp2_op(OP_CFG_ACQ, NSAMP, 32'h0006_0146, 0, 4);
    check32("SC1 QP CTRL bit8 enables short confirmation", {31'd0, dut.short_confirm}, 1);
    check32("SC1 QP CTRL configures three total passes", {29'd0, dut.cfg_confirm}, 3);
    qp2_op(OP_REARM, 0, 0, 0, 0);
    qp2_op(OP_CFG_WINDOW, START_FREQ, STEP, 1, 6);
    block_irq_before = block_irq_count;
    qp2_op(OP_START, 0, 0, 0, 0);
    feed_block_step;
    wait_finish;
    check32("SC1 short returns saved N4 after checks6/8", dut.ac_n_used, 4);
    check32("SC1 short emits one actual accelerator interrupt", block_irq_count - block_irq_before, 1);
    check32("SC1 short retains first-four I mean", dut.ac_mean_i, 1000);
    check32("SC1 short retains first-four Q mean", dut.ac_mean_q, -500);
    check64("SC1 short computes power from saved mean", dut.u_peak_finder.tracker.best_amplitude, 64'd1250000);
    qp2_op(OP_CLR_RESULT, 0, 0, 0, 0);
    qp2_op(OP_GET_DIAG, 0, 0, 0, 0);
    check32("SC1 QP reports saved N", qtag_dt1_o, 4);
    check32("SC1 QP reports candidate exponent", qtag_dt2_o, 32'h0000_0110);

    // CTRL comes only from CFG_ACQ since ABI 5: AXI target 3 is a bad target.
    qp2_op(OP_CFG_ACQ, NSAMP, 32'h0006_0046, 0, 4);
    check32("SC2 baseline CTRL clears short bit", {31'd0, dut.short_confirm}, 0);
    axi_tbl_write(5'd3, 32'h0006_0146);
    check32("SC2 AXI target 3 no longer writes CTRL", {31'd0, dut.short_confirm}, 0);
    qp2_op(OP_CFG_ACQ, NSAMP, 32'h0006_0146, 0, 4);
    check32("SC2 CFG_ACQ sets short bit", {31'd0, dut.short_confirm}, 1);
    check32("SC2 CFG_ACQ sets three passes", {29'd0, dut.cfg_confirm}, 3);
    qp2_op(OP_REARM, 0, 0, 0, 0);
    qp2_op(OP_CFG_WINDOW, START_FREQ, STEP, 1, 6);
    block_irq_before = block_irq_count;
    qp2_op(OP_START, 0, 0, 0, 0);
    feed_block_step;
    wait_finish;
    check32("SC2 AXI short returns saved N4", dut.ac_n_used, 4);
    check32("SC2 AXI short emits one actual interrupt", block_irq_count - block_irq_before, 1);
    check32("SC2 AXI short retains first-four I mean", dut.ac_mean_i, 1000);
    check32("SC2 AXI short retains first-four Q mean", dut.ac_mean_q, -500);

    // A flat response: nothing is ever seen, the search ends nothing-seen (response bit 2, status
    // bit 0), late polls keep the answer, and a later grid run does not inherit the flag.
    qp2_op(OP_CLR_RESULT, 0, 0, 0, 0);
    qp2_op(OP_CFG_ACQ, NSAMP, CTRL_SHIFT, 0, 0);
    qp2_op(OP_CFG_WINDOW, KW_GRID, KW_STEP, KW_NPTS, 1);
    qp2_op(OP_CFG_GDKW, KW_LO, KW_HI, 0, 0);
    qp2_op(OP_RUN_KW, 0, 0, KW_MIN, 32'd100);
    run_kw_line(0, 20000, 0, 2, 0);
    check_kw("K3 flat response", 32'h0ff0_0000, 32'h0000_0004, 5, 32'h50f0_0000, 32'h0ff0_0000);
    qp2_op(OP_GET_FREQ, 0, 0, 0, 0);
    check32("K3 late frequency poll preserves the result", qtag_dt2_o, 32'h0000_0004);
    qp2_op(OP_GET_STATUS, 0, 0, 0, 0);
    check32("K3 late status poll preserves the result", qtag_dt2_o, 32'h0000_0004);
    qp2_op(OP_CLR_RESULT, 0, 0, 0, 0);
    qp2_op(OP_GET_STATUS, 0, 0, 0, 0);
    check32("K3 live nothing_seen status bit0", {31'd0, qtag_dt1_o[0]}, 1);
    check32("K3 deprecated status bit9 remains clear", {31'd0, qtag_dt1_o[9]}, 0);

    qp2_op(OP_CLR_RESULT, 0, 0, 0, 0);
    qp2_op(OP_CFG_WINDOW, START_FREQ, STEP, 1, 1);
    qp2_op(OP_START, 0, 0, 0, 0);
    feed_point(2, 100 * 128, 0);
    wait_finish;
    qp2_op(OP_CLR_RESULT, 0, 0, 0, 0);
    qp2_op(OP_GET_STATUS, 0, 0, 0, 0);
    check32("K3 grid status masks the engine flag", {31'd0, qtag_dt1_o[0]}, 0);

    // The same search as K1 through the split early stop and the REARM handshake: every probe
    // stops at 8 shots, raises the interrupt and parks the IP; the next GET_FREQ is answered
    // after REARM releases it. The powers are the same, so the run is K1's exactly.
    qp2_op(OP_CLR_RESULT, 0, 0, 0, 0);
    qp2_op(OP_CFG_ACQ, NSAMP, CTRL_SPLIT, 0, 4);
    qp2_op(OP_REARM, 0, 0, 0, 0);
    qp2_op(OP_CFG_WINDOW, KW_GRID, KW_STEP, KW_NPTS, 6);
    block_irq_before = block_irq_count;
    qp2_op(OP_RUN_KW, 0, 0, KW_MIN, 32'd100);
    run_kw_line(60000, 1000, 0, 64, 1);
    check_kw("K8 early-stopped probes", 32'h1001_8a80, 32'h000b_0001, 16, 32'h0101_1653, 32'h1ff8_140b);
    check32("K8 every probe stopped early and interrupted", block_irq_count - block_irq_before, 16);
    check32("K8 each probe retired at 8 shots", dut.ac_n_used, 8);

    // DEBUG VIEWS (ABI 5 map). REG3 mirrors the GET_STATUS word, REG4/REG5 are the view
    // pair chosen by REG2, REG6 is the IDENT word; the error bits are sticky
    // until the next START/RUN_*. The last job above was a KW run.
    axi_read(8'h18, axi_rd);
    check32("D0 IDENT register", axi_rd, 32'h4153_0500);

    qp2_op(OP_CLR_RESULT, 0, 0, 0, 0);
    qp2_op(OP_CFG_ACQ, 0, CTRL_SHIFT, 0, 0);
    qp2_op(OP_CFG_WINDOW, START_FREQ, STEP, 32'd3, AVG_T0_SH);
    qp2_op(OP_START, 0, 0, 0, 0);
    feed_point(AVG_T0, 100, 0);
    feed_point(AVG_T0, 200, 0);
    feed_point(AVG_T0, 300, 0);
    wait_finish;
    qp2_op(OP_CLR_RESULT, 0, 0, 0, 0);
    qp2_op(OP_GET_STATUS, 0, 0, 0, 0);
    status_t0 = qtag_dt1_o;
    axi_read(8'h0C, axi_rd);
    check32("D1 AXI STATUS equals the GET_STATUS word", axi_rd, status_t0);
    check32("D1 STATUS point_idx", {16'd0, axi_rd[31:16]}, 32'd2);

    axi_select_view(5'd6);
    qp2_op(OP_GET_DIAG, 0, 0, 0, 0);
    axi_read(8'h10, axi_rd);
    check32("D2 view 6 DT1 is GET_DIAG n_used", axi_rd, qtag_dt1_o);
    axi_read(8'h14, axi_rd);
    check32("D2 view 6 DT2 is the GET_DIAG verdict", axi_rd, qtag_dt2_o);
    axi_select_view(5'd5);
    qp2_op(OP_GET_MEAN, 0, 0, 0, 0);
    axi_read(8'h10, axi_rd);
    check32("D2 view 5 DT1 is the live mean I", axi_rd, qtag_dt1_o);
    axi_read(8'h14, axi_rd);
    check32("D2 view 5 DT2 is the live mean Q", axi_rd, qtag_dt2_o);
    axi_select_view(5'd15);
    axi_read(8'h10, axi_rd);
    check32("D2 view 15 DT1 is the last response", axi_rd, qtag_dt1_o);
    axi_read(8'h14, axi_rd);
    check32("D2 view 15 DT2 is the last response", axi_rd, qtag_dt2_o);

    qp2_op(OP_CLR_RESULT, 0, 0, 0, 0);
    qp2_op(OP_CFG_WINDOW, KW_GRID, KW_STEP, KW_NPTS, 32'd1);
    qp2_op(OP_CFG_GDKW, KW_LO, KW_HI, 32'd0, 32'd0);
    qp2_op(OP_RUN_KW, 32'd0, 32'd0, KW_MIN, 32'd2);
    run_kw_line(60000, 1000, 0, 2, 0);
    check_kw("D3 capped run", 32'h1001_8000, 32'h0002_0002, 7, 32'h70fd_8000, 32'h0ffd_8000);
    axi_select_view(5'd1);
    axi_read(8'h10, axi_rd);
    check32("D3 view 1 engine state idle", {27'd0, axi_rd[16:12]}, 32'd0);
    check32("D3 view 1 capped flag", {31'd0, axi_rd[3]}, 32'd1);
    check32("D3 view 1 last decision is CAPPED", {29'd0, axi_rd[23:21]}, 32'd5);
    axi_read(8'h14, axi_rd);
    check32("D3 view 1 DT2 is {points, iter}", axi_rd, {dut.eng_points, dut.eng_iter});
    check32("D3 five grid points", {16'd0, dut.eng_points}, 32'd5);
    check32("D3 two iterations", {16'd0, dut.eng_iter}, 32'd2);
    axi_select_view(5'd2);
    axi_read(8'h14, axi_rd);
    check32("D3 view 2 DT2 is x", axi_rd, dut.eng_x);
    axi_select_view(5'd3);
    axi_read(8'h10, axi_rd);
    check32("D3 view 3 DT1 is the border width", axi_rd,
            dut.u_gradient_engine.points.hi - dut.u_gradient_engine.points.lo);
    axi_read(8'h14, axi_rd);
    check32("D3 view 3 DT2 is the last move", axi_rd, dut.u_gradient_engine.planner.step);

    axi_select_view(5'd8);
    axi_read(8'h10, axi_rd);
    check32("D4 view 8 DT1 start_freq", axi_rd, KW_GRID);
    axi_read(8'h14, axi_rd);
    check32("D4 view 8 DT2 step", axi_rd, KW_STEP);
    axi_select_view(5'd11);
    axi_read(8'h14, axi_rd);
    check32("D4 view 11 DT2 f_hi", axi_rd, KW_HI);
    axi_select_view(5'd12);
    axi_read(8'h10, axi_rd);
    check32("D4 view 12 DT1 is free", axi_rd, 32'd0);
    axi_read(8'h14, axi_rd);
    check32("D4 view 12 DT2 CTRL live bits", axi_rd, CTRL_SHIFT & 32'h000E_01D1);
    axi_tbl_write(5'd4, 32'd77);
    axi_select_view(5'd13);
    axi_read(8'h10, axi_rd);
    check32("D4 view 13 DT1 block_tol", axi_rd, 32'd77);
    axi_read(8'h14, axi_rd);
    check32("D4 view 13 DT2 last target", {27'd0, axi_rd[4:0]}, 32'd4);
    commit_before = {16'd0, axi_rd[31:16]};
    axi_tbl_write(5'd4, 32'd0);
    axi_read(8'h14, axi_rd);
    check32("D4 view 13 commit count advanced by one", {16'd0, axi_rd[31:16]}, commit_before + 1);

    axi_select_view(5'd0);
    qp2_op(OP_CLR_RESULT, 0, 0, 0, 0);
    qp2_op(OP_CFG_WINDOW, START_FREQ, STEP, 32'd1, AVG_T0_SH);
    qp2_op(OP_START, 0, 0, 0, 0);
    axi_read(8'h14, axi_rd);
    check32("D5 errors clear at START", {27'd0, axi_rd[4:0]}, 32'd0);
    qp2_op(OP_START, 0, 0, 0, 0);
    axi_read(8'h14, axi_rd);
    check32("D5 START while busy", {27'd0, axi_rd[4:0]}, 32'b00001);
    qp2_op(5'd24, 0, 0, 0, 0);
    qp2_op(5'd15, 0, 0, 0, 0);
    qp2_op(5'd12, 0, 0, 0, 0);
    check32("D5 free op 12 starts nothing", {31'd0, dut.eng_busy}, 32'd0);
    axi_read(8'h14, axi_rd);
    check32("D5 unknown op flagged, CFG_INTERRUPT ignored", {27'd0, axi_rd[4:0]}, 32'b00011);
    axi_tbl_write(5'd7, 32'd1);
    axi_read(8'h14, axi_rd);
    check32("D5 bad AXI target", {27'd0, axi_rd[4:0]}, 32'b01011);
    feed_point(AVG_T0, 100, 0);
    wait_finish;
    qp2_op(OP_GET_STATUS, 0, 0, 0, 0);
    axi_read(8'h14, axi_rd);
    check32("D5 read while the result is held", {27'd0, axi_rd[4:0]}, 32'b01111);
    check32("D5 no stray power", {31'd0, axi_rd[4]}, 32'd0);
    qp2_op(OP_CLR_RESULT, 0, 0, 0, 0);
    axi_read(8'h10, axi_rd);
    check32("D5 view 0 last op is CLR_RESULT", {27'd0, axi_rd[23:19]}, {27'd0, OP_CLR_RESULT});
    check32("D5 view 0 finish_seen", {31'd0, axi_rd[7]}, 32'd1);
    check32("D5 view 0 ready", {31'd0, axi_rd[12]}, 32'd1);

    axi_select_view(5'd31);
    axi_read(8'h10, axi_rd);
    check32("D6 the view select keeps 4 bits: 31 selects view 15", {28'd0, dut.monitor.read_sel}, 32'd15);
    check32("D6 select 31 reads the last response (view 15)", axi_rd, qtag_dt1_o);
    axi_select_view(5'd0);

    check32("D7 c_debug_do counted every opcode strobe", op_pulses, op_calls);
    check32("D7 c_data_do follows the selected view", c_data_do, dut.dbg_dt1);
    check32("D7 c_debug_do idle handshake bits", {28'd0, c_debug_do[25:22]}, 32'b1000);

    if (errors == 0)
      $display("ALL TESTS PASSED");
    else
      $fatal(1, "%0d FAILURE(S)", errors);

    $finish;
  end

endmodule
