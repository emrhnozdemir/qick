`timescale 1ns / 1ps

module tb_adaptive_sweep;

  localparam NSAMP = 32'd190;
  localparam START_FREQ = 32'h1000_0000;
  localparam STEP = 32'h0010_0000;
  localparam N_POINTS = 32'd5;
  localparam AVG_T0 = 32'd4;
  localparam AVG_MAD = 32'd16;

  localparam [31:0] CTRL_SHIFT = 32'h0000_0022;
  localparam [31:0] CTRL_MADSTOP = 32'h0000_0062;
  localparam [31:0] CTRL_RAW = 32'h0000_0000;
  localparam [31:0] CTRL_MEAN = 32'h0000_0024;

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
  wire [31:0] s_axi_rdata;
  wire s_axi_arready;

  integer errors;

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
    .s_axi_rready  (1'b1)
  );

  wire [4:0] l2_190, l2_1000, l2_60, l2_1025, l2_1, l2_0;

  log2_floor u_l2_190 (.v_i(32'd190), .y_o(l2_190));
  log2_floor u_l2_1000 (.v_i(32'd1000), .y_o(l2_1000));
  log2_floor u_l2_60 (.v_i(32'd60), .y_o(l2_60));
  log2_floor u_l2_1025 (.v_i(32'd1025), .y_o(l2_1025));
  log2_floor u_l2_1 (.v_i(32'd1), .y_o(l2_1));
  log2_floor u_l2_0 (.v_i(32'd0), .y_o(l2_0));

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

  task automatic check128(input string name, input [127:0] got, input [127:0] exp);
    begin
      if (got !== exp) begin
        $display("FAIL %0s: got %0d (0x%032x), expected %0d (0x%032x)", name, got, got, exp, exp);
        errors = errors + 1;
      end else begin
        $display("PASS %0s = %0d (0x%032x)", name, got, got);
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
        qp2_op(5'd10, 32'd0, 32'd0, 32'd0, 32'd0);
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
    #500000;
    $display("FAIL: global timeout");
    $finish;
  end

  integer p;
  reg [31:0] amp_of_point [0:4];
  reg [31:0] status_t0;
  reg [31:0] n_used_t1, n_used_t2;
  reg [31:0] status_t1, status_t2;
  reg [127:0] raw_sum_expect;
  integer grid_before, search_before;

  initial begin
    errors = 0;
    arm_taken = 0;
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

    check32("L2 flog2(190)", {27'd0, l2_190}, 32'd7);
    check32("L2 flog2(1000)", {27'd0, l2_1000}, 32'd9);
    check32("L2 flog2(60)", {27'd0, l2_60}, 32'd5);
    check32("L2 flog2(1025)", {27'd0, l2_1025}, 32'd10);
    check32("L2 flog2(1)", {27'd0, l2_1}, 32'd0);
    check32("L2 flog2(0)", {27'd0, l2_0}, 32'd0);

    qp2_op(5'd2, NSAMP, CTRL_SHIFT, 32'd0, 32'd0);
    qp2_op(5'd0, START_FREQ, STEP, N_POINTS, AVG_T0);
    qp2_op(5'd1, 32'd0, 32'd0, 32'd0, 32'd0);

    for (p = 0; p < 5; p = p + 1)
      feed_point(AVG_T0, amp_of_point[p], 0);

    wait_finish;
    check32("T0 peak freq_word", qtag_dt1_o, START_FREQ + 2 * STEP);
    check32("T0 rdy after finish", {31'd0, qtag_rdy_o}, 32'd1);
    check128("T0 peak power", dut.u_peak_finder_wide.max_amplitude, 128'd250000);

    qp2_op(5'd10, 32'd0, 32'd0, 32'd0, 32'd0);
    check32("T0 result survives a late OP10", qtag_dt1_o,
            START_FREQ + 2 * STEP);
    qp2_op(5'd3, 32'd0, 32'd0, 32'd0, 32'd0);
    check32("T0 result survives a late OP3", qtag_dt1_o,
            START_FREQ + 2 * STEP);
    qp2_op(5'd5, 32'd0, 32'd0, 32'd0, 32'd0);
    check32("T0 result survives a late OP5", qtag_dt1_o,
            START_FREQ + 2 * STEP);
    qp2_op(5'd11, 32'd0, 32'd0, 32'd0, 32'd0);
    check32("T0 result survives a late OP11", qtag_dt1_o,
            START_FREQ + 2 * STEP);

    qp2_op(5'd13, 32'd0, 32'd0, 32'd0, 32'd0);
    check32("T0 vld cleared by OP13", {31'd0, qtag_vld_o}, 32'd0);

    qp2_op(5'd3, 32'd0, 32'd0, 32'd0, 32'd0);
    status_t0 = qtag_dt1_o;
    check32("T0 status point_idx", {16'd0, status_t0[31:16]}, 32'd4);
    check32("T0 status reduce_sel", {29'd0, status_t0[6:4]}, 32'd1);
    check32("T0 status prescale_en", {31'd0, status_t0[9]}, 32'd1);
    check32("T0 status estop_en", {31'd0, status_t0[10]}, 32'd0);
    check32("T0 status dest", {31'd0, status_t0[11]}, 32'd0);
    check32("T0 status busy", {31'd0, status_t0[2]}, 32'd0);
    check32("T0 status finish_seen", {31'd0, status_t0[1]}, 32'd1);
    check32("T0 status freq_at_max", qtag_dt2_o, START_FREQ + 2 * STEP);

    qp2_op(5'd2, NSAMP, CTRL_MADSTOP, 32'd0, 32'd4);
    qp2_op(5'd0, START_FREQ, STEP, 32'd1, AVG_MAD);
    qp2_op(5'd1, 32'd0, 32'd0, 32'd0, 32'd0);

    feed_alternating(AVG_MAD, 100 * 128, 102 * 128);
    wait_finish;

    qp2_op(5'd13, 32'd0, 32'd0, 32'd0, 32'd0);
    qp2_op(5'd5, 32'd0, 32'd0, 32'd0, 32'd0);
    n_used_t1 = qtag_dt1_o;
    qp2_op(5'd3, 32'd0, 32'd0, 32'd0, 32'd0);
    status_t1 = qtag_dt1_o;
    check32("T1 n_used (no table)", n_used_t1, AVG_MAD);
    check32("T1 early_stop (no table)", {31'd0, status_t1[8]}, 32'd0);
    check32("T1 estop_en", {31'd0, status_t1[10]}, 32'd1);

    axi_write(8'h04, 32'hFFFF_FFFF);
    axi_write(8'h08, 32'h0000_3FFF);
    axi_write(8'h00, 32'h0000_0202);
    axi_write(8'h00, 32'h8000_0202);
    repeat (40) @(posedge clk);

    qp2_op(5'd2, NSAMP, CTRL_MADSTOP, 32'd0, 32'd4);
    qp2_op(5'd0, START_FREQ, STEP, 32'd1, AVG_MAD);
    qp2_op(5'd1, 32'd0, 32'd0, 32'd0, 32'd0);

    feed_alternating(AVG_MAD, 100 * 128, 102 * 128);
    wait_finish;

    qp2_op(5'd13, 32'd0, 32'd0, 32'd0, 32'd0);
    qp2_op(5'd5, 32'd0, 32'd0, 32'd0, 32'd0);
    n_used_t2 = qtag_dt1_o;
    qp2_op(5'd3, 32'd0, 32'd0, 32'd0, 32'd0);
    status_t2 = qtag_dt1_o;
    check32("T2 n_used (AXI table)", n_used_t2, 32'd4);
    check32("T2 early_stop (AXI table)", {31'd0, status_t2[8]}, 32'd1);
    check128("T2 stopped-epoch power", dut.u_peak_finder_wide.max_amplitude, 128'd10201);

    raw_sum_expect = 128'd4 * 128'd500 * 128'd128;
    raw_sum_expect = raw_sum_expect * raw_sum_expect;

    qp2_op(5'd2, NSAMP, CTRL_RAW, 32'd0, 32'd0);
    qp2_op(5'd0, START_FREQ, STEP, N_POINTS, AVG_T0);
    qp2_op(5'd1, 32'd0, 32'd0, 32'd0, 32'd0);

    for (p = 0; p < 5; p = p + 1)
      feed_point(AVG_T0, amp_of_point[p], 0);

    wait_finish;
    check32("T3 raw-sum peak freq_word", qtag_dt1_o, START_FREQ + 2 * STEP);
    check128("T3 raw-sum peak power", dut.u_peak_finder_wide.max_amplitude, raw_sum_expect);
    qp2_op(5'd13, 32'd0, 32'd0, 32'd0, 32'd0);
    qp2_op(5'd3, 32'd0, 32'd0, 32'd0, 32'd0);
    check32("T3 status reduce_sel", {29'd0, qtag_dt1_o[6:4]}, 32'd0);
    check32("T3 status prescale_en", {31'd0, qtag_dt1_o[9]}, 32'd0);

    qp2_op(5'd2, NSAMP, CTRL_MEAN, 32'd0, 32'd0);
    qp2_op(5'd0, START_FREQ, STEP, 32'd1, AVG_T0);
    qp2_op(5'd1, 32'd0, 32'd0, 32'd0, 32'd0);

    feed_alternating(AVG_T0, 100 * 128, 102 * 128);
    wait_finish;

    check128("T4 running-mean power", dut.u_peak_finder_wide.max_amplitude, 128'd10201);
    qp2_op(5'd13, 32'd0, 32'd0, 32'd0, 32'd0);
    qp2_op(5'd3, 32'd0, 32'd0, 32'd0, 32'd0);
    check32("T4 status reduce_sel", {29'd0, qtag_dt1_o[6:4]}, 32'd2);

    qp2_op(5'd13, 32'd0, 32'd0, 32'd0, 32'd0);
    qp2_op(5'd2, NSAMP, CTRL_SHIFT, 32'd0, 32'd0);
    qp2_op(5'd0, START_FREQ, STEP, N_POINTS, 32'd2);
    qp2_op(5'd12, 32'd0, 32'hFFFF_FFFF, 32'd1, 32'd2);

    grid_before = grid_valid_cnt;
    search_before = search_valid_cnt;

    qp2_op(5'd6, START_FREQ, 32'h0002_0000, 32'd0, 32'd4);
    run_probes(2, 100 * 128, 400);

    check32("T5 gd result x", qtag_dt1_o, START_FREQ);
    check32("T5 gd converged word", qtag_dt2_o, 32'h0002_0001);
    check32("T5 grid path stayed idle", grid_valid_cnt - grid_before, 32'd0);
    check32("T5 search path saw every probe", search_valid_cnt - search_before, 32'd8);

    qp2_op(5'd13, 32'd0, 32'd0, 32'd0, 32'd0);
    qp2_op(5'd3, 32'd0, 32'd0, 32'd0, 32'd0);
    check32("T5 status dest", {31'd0, qtag_dt1_o[11]}, 32'd1);

    if (errors == 0)
      $display("ALL TESTS PASSED");
    else
      $display("%0d FAILURE(S)", errors);

    $finish;
  end

endmodule
