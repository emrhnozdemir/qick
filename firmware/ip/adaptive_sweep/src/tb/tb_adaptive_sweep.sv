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
  localparam [31:0] CTRL_MEAN32 = 32'h0000_0006;
  localparam [31:0] CTRL_MEAN = 32'h0000_0024;
  localparam [31:0] CTRL_SPLIT = 32'h0004_0CC6;
  localparam [31:0] CTRL_SPLIT_HOLD = 32'h0004_0CD6;
  localparam [31:0] CTRL_CKDIFF = 32'h0004_0D46;
  localparam [31:0] CTRL_HSPLIT = 32'h0006_8CC6;
  localparam [31:0] CTRL_QUARTER = 32'h000B_0CC6;

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

  reg div_start;
  reg signed [63:0] div_num;
  reg [31:0] div_den;
  reg [5:0] div_kp1;
  reg [53:0] div_mag;
  reg [4:0] div_sft;
  wire div_busy;
  wire div_done;
  wire signed [31:0] div_q;

  gm_divider u_div_tb (
    .clk     (clk),
    .rst_n   (rst_n),
    .start_i (div_start),
    .num_i   (div_num),
    .den_i   (div_den),
    .kp1_i   (div_kp1),
    .mag_i   (div_mag),
    .sft_i   (div_sft),
    .busy_o  (div_busy),
    .done_o  (div_done),
    .q_o     (div_q)
  );

  function automatic [5:0] f_ctz(input [31:0] v);
    integer k;
    reg [31:0] lsb;
    reg [5:0] r;
    begin
      lsb = v & ((~v) + 32'd1);
      r = 6'd0;
      for (k = 1; k < 32; k = k + 1) begin
        if (lsb[k]) begin
          r = k[5:0];
        end else begin
          r = r;
        end
      end
      f_ctz = r;
    end
  endfunction

  function automatic [58:0] f_magic(input [31:0] d);
    reg [127:0] pw;
    reg [127:0] mg;
    reg [127:0] er;
    reg [53:0] mag_f;
    reg [4:0] sft_f;
    integer p;
    integer s;
    begin
      mag_f = 54'd0;
      sft_f = 5'd0;
      for (p = 78; p >= 52; p = p - 1) begin
        s = p - 52;
        pw = 128'd1 << p;
        mg = (pw + {96'd0, d} - 128'd1) / {96'd0, d};
        er = mg * {96'd0, d} - pw;
        if (er <= (128'd1 << s)) begin
          mag_f = mg[53:0];
          sft_f = s[4:0];
        end else begin
          mag_f = mag_f;
          sft_f = sft_f;
        end
      end
      f_magic = {mag_f, sft_f};
    end
  endfunction

  task automatic div_check(input string name, input longint num, input longint den, input int expq);
    integer guard;
    longint d_odd;
    reg [5:0] tz;
    reg [58:0] ms;
    begin
      @(posedge clk);
      tz = f_ctz(den[31:0]);
      d_odd = den >> tz;
      ms = f_magic(d_odd[31:0]);
      div_num <= num;
      div_den <= den[31:0];
      div_kp1 <= tz + 6'd1;
      div_mag <= ms[58:5];
      div_sft <= ms[4:0];
      div_start <= 1'b1;
      @(posedge clk);
      div_start <= 1'b0;
      guard = 0;
      while (!div_done && (guard < 20)) begin
        @(posedge clk);
        guard = guard + 1;
      end
      if (guard >= 20) begin
        $display("FAIL %0s: divider timeout", name);
        errors = errors + 1;
      end else begin
        check32(name, div_q, expq);
      end
    end
  endtask

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

  task automatic axi_tbl_write(input [1:0] target, input [5:0] addr, input [31:0] data, input [13:0] hi, input [6:0] len);
    begin
      axi_write(8'h04, data);
      axi_write(8'h08, {18'd0, hi});
      axi_write(8'h0C, {25'd0, len});
      axi_write(8'h00, {axi_tog, 21'd0, target, 2'd0, addr});
      axi_tog = ~axi_tog;
      axi_write(8'h00, {axi_tog, 21'd0, target, 2'd0, addr});
      repeat (10) @(posedge clk);
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
  reg [58:0] tb_ms;
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
    div_start = 1'b0;
    div_num = 64'd0;
    div_den = 32'd1;
    div_kp1 = 6'd1;
    div_mag = 54'd0;
    div_sft = 5'd0;

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

    check32("C0 ctz(1000)", {26'd0, f_ctz(32'd1000)}, 32'd3);
    check32("C1 ctz(96)", {26'd0, f_ctz(32'd96)}, 32'd5);
    check32("C2 ctz(1)", {26'd0, f_ctz(32'd1)}, 32'd0);
    check32("C3 ctz(1048576)", {26'd0, f_ctz(32'd1048576)}, 32'd20);

    tb_ms = f_magic(32'd3);
    check64("M0 magic(3) M", {10'd0, tb_ms[58:5]}, 64'd3002399751580331);
    check32("M0 magic(3) sft", {27'd0, tb_ms[4:0]}, 32'd1);
    tb_ms = f_magic(32'd25);
    check64("M1 magic(25) M", {10'd0, tb_ms[58:5]}, 64'd1441151880758559);
    check32("M1 magic(25) sft", {27'd0, tb_ms[4:0]}, 32'd3);
    tb_ms = f_magic(32'd15625);
    check64("M2 magic(15625) M", {10'd0, tb_ms[58:5]}, 64'd2361183241434823);
    check32("M2 magic(15625) sft", {27'd0, tb_ms[4:0]}, 32'd13);

    div_check("D0 10/4", 64'sd10, 4, 3);
    div_check("D1 -10/4", -64'sd10, 4, -2);
    div_check("D2 0/5", 64'sd0, 5, 0);
    div_check("D3 11988/12", 64'sd11988, 12, 999);
    div_check("D4 9600000/100", 64'sd9600000, 100, 96000);
    div_check("D5 7/3", 64'sd7, 3, 2);
    div_check("D6 8/3", 64'sd8, 3, 3);
    div_check("D7 -8/3", -64'sd8, 3, -3);
    div_check("D8 -7/3", -64'sd7, 3, -2);
    div_check("D9 1/2 rhu", 64'sd1, 2, 1);
    div_check("D10 -1/2 rhu", -64'sd1, 2, 0);
    div_check("D11 -2^51/2^20", -64'sd2251799813685248, 32'd1048576, -2147483648);
    div_check("D12 max/2^20", 64'sd2251799812636672, 32'd1048576, 2147483647);
    div_check("D13 1000/1000", 64'sd1000, 1000, 1);
    div_check("D14 max/2^31", 64'sd4611686016279904256, 64'd2147483648,
              2147483647);
    div_check("D15 -2^62/2^31", -64'sd4611686018427387904, 64'd2147483648,
              -2147483648);
    div_check("D16 big odd-part cap", 64'sd1431652352000000, 64'd1431652352,
              1000000);

    qp2_op(5'd2, NSAMP, CTRL_SHIFT, 32'd0, 32'd0);
    qp2_op(5'd0, START_FREQ, STEP, N_POINTS, AVG_T0);
    qp2_op(5'd1, 32'd0, 32'd0, 32'd0, 32'd0);

    for (p = 0; p < 5; p = p + 1)
      feed_point(AVG_T0, amp_of_point[p], 0);

    wait_finish;
    check32("T0 peak freq_word", qtag_dt1_o, START_FREQ + 2 * STEP);
    check32("T0 rdy after finish", {31'd0, qtag_rdy_o}, 32'd1);
    check64("T0 peak power", dut.u_peak_finder_wide.max_amplitude, 64'd250000);

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

    qp2_op(5'd10, 32'd0, 32'd0, 32'd0, 32'd0);
    qp2_op(5'd4, 32'd0, 32'd0, 32'd0, 32'd0);
    n_used_t1 = qtag_dt1_o;
    qp2_op(5'd3, 32'd0, 32'd0, 32'd0, 32'd0);
    status_t1 = qtag_dt1_o;
    check32("T1 n_used (no table)", n_used_t1, AVG_MAD);
    check32("T1 early_stop (no table)", {31'd0, status_t1[8]}, 32'd0);
    check32("T1 estop_en", {31'd0, status_t1[10]}, 32'd1);

    axi_tbl_write(2'd2, 6'd2, 32'hFFFF_FFFF, 14'h3FFF, 7'd0);
    repeat (40) @(posedge clk);

    qp2_op(5'd2, NSAMP, CTRL_MADSTOP, 32'd0, 32'd4);
    qp2_op(5'd0, START_FREQ, STEP, 32'd1, AVG_MAD);
    qp2_op(5'd1, 32'd0, 32'd0, 32'd0, 32'd0);

    feed_alternating(AVG_MAD, 100 * 128, 102 * 128);
    wait_finish;

    qp2_op(5'd10, 32'd0, 32'd0, 32'd0, 32'd0);
    qp2_op(5'd4, 32'd0, 32'd0, 32'd0, 32'd0);
    n_used_t2 = qtag_dt1_o;
    qp2_op(5'd3, 32'd0, 32'd0, 32'd0, 32'd0);
    status_t2 = qtag_dt1_o;
    check32("T2 n_used (AXI table)", n_used_t2, 32'd4);
    check32("T2 early_stop (AXI table)", {31'd0, status_t2[8]}, 32'd1);
    check64("T2 stopped-epoch power", dut.u_peak_finder_wide.max_amplitude, 64'd10201);

    axi_tbl_write(2'd2, 6'd1, 32'hFFFF_FFFF, 14'h3FFF, 7'd0);
    repeat (40) @(posedge clk);

    qp2_op(5'd2, NSAMP, CTRL_MADSTOP, 32'd0, 32'd2);
    qp2_op(5'd0, START_FREQ, STEP, 32'd1, AVG_MAD);
    qp2_op(5'd1, 32'd0, 32'd0, 32'd0, 32'd0);

    feed_alternating(AVG_MAD, 100 * 128, 102 * 128);
    wait_finish;

    qp2_op(5'd10, 32'd0, 32'd0, 32'd0, 32'd0);
    qp2_op(5'd4, 32'd0, 32'd0, 32'd0, 32'd0);
    check32("T2b n_used (n=2 epoch)", qtag_dt1_o, 32'd2);
    qp2_op(5'd3, 32'd0, 32'd0, 32'd0, 32'd0);
    check32("T2b early_stop", {31'd0, qtag_dt1_o[8]}, 32'd1);
    check64("T2b n=2 epoch power", dut.u_peak_finder_wide.max_amplitude, 64'd10201);

    qp2_op(5'd2, NSAMP, CTRL_MEAN32, 32'd0, 32'd0);
    qp2_op(5'd0, START_FREQ, STEP, 32'd1, 32'd1);
    qp2_op(5'd1, 32'd0, 32'd0, 32'd0, 32'd0);

    feed_point(1, 32'h7FFF_FFFF, 32'h8000_0000);

    wait_finish;
    check32("T3 rail peak freq_word", qtag_dt1_o, START_FREQ);
    check64("T3 int32 rail power", dut.u_peak_finder_wide.max_amplitude, 64'h7FFF_FFFF_0000_0001);
    qp2_op(5'd10, 32'd0, 32'd0, 32'd0, 32'd0);
    qp2_op(5'd3, 32'd0, 32'd0, 32'd0, 32'd0);
    check32("T3 status reduce_sel", {29'd0, qtag_dt1_o[6:4]}, 32'd3);
    check32("T3 status prescale_en", {31'd0, qtag_dt1_o[9]}, 32'd0);

    qp2_op(5'd2, NSAMP, CTRL_MEAN, 32'd0, 32'd0);
    qp2_op(5'd0, START_FREQ, STEP, 32'd1, AVG_T0);
    qp2_op(5'd1, 32'd0, 32'd0, 32'd0, 32'd0);

    feed_alternating(AVG_T0, 100 * 128, 102 * 128);
    wait_finish;

    check64("T4 running-mean power", dut.u_peak_finder_wide.max_amplitude, 64'd10201);
    qp2_op(5'd10, 32'd0, 32'd0, 32'd0, 32'd0);
    qp2_op(5'd3, 32'd0, 32'd0, 32'd0, 32'd0);
    check32("T4 status reduce_sel", {29'd0, qtag_dt1_o[6:4]}, 32'd2);

    qp2_op(5'd10, 32'd0, 32'd0, 32'd0, 32'd0);
    qp2_op(5'd2, NSAMP, CTRL_SHIFT, 32'd0, 32'd0);
    qp2_op(5'd0, START_FREQ, STEP, N_POINTS, 32'd2);
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

    qp2_op(5'd10, 32'd0, 32'd0, 32'd0, 32'd0);
    qp2_op(5'd2, NSAMP, CTRL_SPLIT, 32'd0, 32'd8);
    qp2_op(5'd0, START_FREQ, STEP, 32'd1, 32'd64);
    qp2_op(5'd1, 32'd0, 32'd0, 32'd0, 32'd0);

    feed_point(64, 1000, 500);
    wait_finish;

    check32("T6 split freq", qtag_dt1_o, START_FREQ);
    check64("T6 split power", dut.u_peak_finder_wide.max_amplitude, 64'd1250000);
    qp2_op(5'd10, 32'd0, 32'd0, 32'd0, 32'd0);
    qp2_op(5'd4, 32'd0, 32'd0, 32'd0, 32'd0);
    check32("T6 n_used", qtag_dt1_o, 32'd8);
    check32("T6 diag word", qtag_dt2_o, 32'h0000_0118);
    qp2_op(5'd3, 32'd0, 32'd0, 32'd0, 32'd0);
    check32("T6 status early_stop", {31'd0, qtag_dt1_o[8]}, 32'd1);
    check32("T6 status drift", {31'd0, qtag_dt1_o[0]}, 32'd0);
    qp2_op(5'd11, 32'd0, 32'd0, 32'd0, 32'd0);
    check32("T6 mean I", qtag_dt1_o, 32'd1000);
    check32("T6 mean Q", qtag_dt2_o, 32'd500);
    qp2_op(5'd12, 32'd0, 32'd0, 32'd0, 32'd0);
    check32("T6 log entry 0", qtag_dt1_o, 32'h8000_0118);
    check32("T6 log count", qtag_dt2_o, 32'd1);
    qp2_op(5'd12, 32'd1, 32'd0, 32'd0, 32'd0);
    check32("T6 log idx1 invalid", {31'd0, qtag_dt1_o[31]}, 32'd0);

    qp2_op(5'd2, NSAMP, CTRL_SPLIT_HOLD, 32'd0, 32'd8);
    qp2_op(5'd0, START_FREQ, STEP, 32'd1, 32'd64);
    qp2_op(5'd1, 32'd0, 32'd0, 32'd0, 32'd0);

    feed_point(64, 1000, 500);
    wait_finish;

    check64("T6b drain power", dut.u_peak_finder_wide.max_amplitude, 64'd1250000);
    qp2_op(5'd10, 32'd0, 32'd0, 32'd0, 32'd0);
    qp2_op(5'd4, 32'd0, 32'd0, 32'd0, 32'd0);
    check32("T6b n_used", qtag_dt1_o, 32'd8);
    check32("T6b diag word", qtag_dt2_o, 32'h0000_0118);

    qp2_op(5'd2, NSAMP, CTRL_CKDIFF, 32'd0, 32'd8);
    qp2_op(5'd0, START_FREQ, STEP, 32'd1, 32'd64);
    qp2_op(5'd1, 32'd0, 32'd0, 32'd0, 32'd0);

    feed_point(64, -1500, 250);
    wait_finish;

    check64("T7 ckdiff power", dut.u_peak_finder_wide.max_amplitude, 64'd2312500);
    qp2_op(5'd10, 32'd0, 32'd0, 32'd0, 32'd0);
    qp2_op(5'd4, 32'd0, 32'd0, 32'd0, 32'd0);
    check32("T7 n_used", qtag_dt1_o, 32'd16);
    check32("T7 diag word", qtag_dt2_o, 32'h0000_0120);
    qp2_op(5'd11, 32'd0, 32'd0, 32'd0, 32'd0);
    check32("T7 mean I", qtag_dt1_o, 32'hFFFF_FA24);
    check32("T7 mean Q", qtag_dt2_o, 32'd250);

    qp2_op(5'd2, NSAMP, CTRL_HSPLIT, 32'd0, 32'd12);
    qp2_op(5'd0, START_FREQ, STEP, 32'd1, 32'd64);
    qp2_op(5'd1, 32'd0, 32'd0, 32'd0, 32'd0);

    feed_point(64, 999, -999);
    wait_finish;

    check64("T8 hsplit power", dut.u_peak_finder_wide.max_amplitude, 64'd1996002);
    qp2_op(5'd10, 32'd0, 32'd0, 32'd0, 32'd0);
    qp2_op(5'd4, 32'd0, 32'd0, 32'd0, 32'd0);
    check32("T8 n_used", qtag_dt1_o, 32'd12);
    check32("T8 diag word", qtag_dt2_o, 32'h0000_0111);
    qp2_op(5'd12, 32'd0, 32'd0, 32'd0, 32'd0);
    check32("T8 log entry 0", qtag_dt1_o, 32'h8000_0111);
    qp2_op(5'd11, 32'd0, 32'd0, 32'd0, 32'd0);
    check32("T8 mean I", qtag_dt1_o, 32'd999);
    check32("T8 mean Q", qtag_dt2_o, 32'hFFFF_FC19);

    qp2_op(5'd13, 32'h51EB851F, 32'h00C51EB8, 32'd3, 32'd0);
    qp2_op(5'd2, NSAMP, CTRL_SPLIT, 32'd0, 32'd4);
    qp2_op(5'd0, START_FREQ, STEP, 32'd1, 32'd100);
    qp2_op(5'd1, 32'd0, 32'd0, 32'd0, 32'd0);

    feed_alternating(100, 128000, 64000);
    wait_finish;

    check64("T9 cap power", dut.u_peak_finder_wide.max_amplitude, 64'd9216000000);
    qp2_op(5'd10, 32'd0, 32'd0, 32'd0, 32'd0);
    qp2_op(5'd4, 32'd0, 32'd0, 32'd0, 32'd0);
    check32("T9 n_used", qtag_dt1_o, 32'd100);
    check32("T9 diag word", qtag_dt2_o, 32'h0001_0204);
    qp2_op(5'd3, 32'd0, 32'd0, 32'd0, 32'd0);
    check32("T9 status early_stop", {31'd0, qtag_dt1_o[8]}, 32'd0);
    qp2_op(5'd11, 32'd0, 32'd0, 32'd0, 32'd0);
    check32("T9 mean I", qtag_dt1_o, 32'd96000);
    check32("T9 mean Q", qtag_dt2_o, 32'd0);
    qp2_op(5'd12, 32'd0, 32'd0, 32'd0, 32'd0);
    check32("T9 log entry 0", qtag_dt1_o, 32'h8000_0204);
    check32("T9 log count", qtag_dt2_o, 32'd1);

    qp2_op(5'd2, NSAMP, CTRL_QUARTER, 32'd0, 32'd8);
    qp2_op(5'd0, START_FREQ, STEP, 32'd1, 32'd64);
    qp2_op(5'd1, 32'd0, 32'd0, 32'd0, 32'd0);

    feed_point(64, 2000, -1000);
    wait_finish;

    check32("TQ1 quarter freq", qtag_dt1_o, START_FREQ);
    check64("TQ1 quarter power", dut.u_peak_finder_wide.max_amplitude, 64'd5000000);
    qp2_op(5'd10, 32'd0, 32'd0, 32'd0, 32'd0);
    qp2_op(5'd4, 32'd0, 32'd0, 32'd0, 32'd0);
    check32("TQ1 n_used", qtag_dt1_o, 32'd16);
    check32("TQ1 diag word", qtag_dt2_o, 32'h0000_0120);
    qp2_op(5'd11, 32'd0, 32'd0, 32'd0, 32'd0);
    check32("TQ1 mean I", qtag_dt1_o, 32'd2000);
    check32("TQ1 mean Q", qtag_dt2_o, 32'hFFFF_FC18);
    qp2_op(5'd12, 32'd0, 32'd0, 32'd0, 32'd0);
    check32("TQ1 log entry 0", qtag_dt1_o, 32'h8000_0120);
    check32("TQ1 log count", qtag_dt2_o, 32'd1);

    qp2_op(5'd2, NSAMP, CTRL_QUARTER, 32'd0, 32'd20);
    qp2_op(5'd0, START_FREQ, STEP, 32'd1, 32'd64);
    qp2_op(5'd1, 32'd0, 32'd0, 32'd0, 32'd0);

    feed_point(64, -3000, 700);
    wait_finish;

    check64("TQ2 m5 power", dut.u_peak_finder_wide.max_amplitude, 64'd9490000);
    qp2_op(5'd10, 32'd0, 32'd0, 32'd0, 32'd0);
    qp2_op(5'd4, 32'd0, 32'd0, 32'd0, 32'd0);
    check32("TQ2 n_used", qtag_dt1_o, 32'd20);
    check32("TQ2 diag word", qtag_dt2_o, 32'h0000_0112);
    qp2_op(5'd11, 32'd0, 32'd0, 32'd0, 32'd0);
    check32("TQ2 mean I", qtag_dt1_o, 32'hFFFF_F448);
    check32("TQ2 mean Q", qtag_dt2_o, 32'h0000_02BC);
    qp2_op(5'd12, 32'd0, 32'd0, 32'd0, 32'd0);
    check32("TQ2 log entry 0", qtag_dt1_o, 32'h8000_0112);

    qp2_op(5'd2, NSAMP, CTRL_QUARTER, 32'd0, 32'd28);
    qp2_op(5'd0, START_FREQ, STEP, 32'd1, 32'd64);
    qp2_op(5'd1, 32'd0, 32'd0, 32'd0, 32'd0);

    feed_point(64, 511, -512);
    wait_finish;

    check64("TQ3 m7 power", dut.u_peak_finder_wide.max_amplitude, 64'd523265);
    qp2_op(5'd10, 32'd0, 32'd0, 32'd0, 32'd0);
    qp2_op(5'd4, 32'd0, 32'd0, 32'd0, 32'd0);
    check32("TQ3 n_used", qtag_dt1_o, 32'd28);
    check32("TQ3 diag word", qtag_dt2_o, 32'h0000_0113);
    qp2_op(5'd11, 32'd0, 32'd0, 32'd0, 32'd0);
    check32("TQ3 mean I", qtag_dt1_o, 32'd511);
    check32("TQ3 mean Q", qtag_dt2_o, 32'hFFFF_FE00);
    qp2_op(5'd12, 32'd0, 32'd0, 32'd0, 32'd0);
    check32("TQ3 log entry 0", qtag_dt1_o, 32'h8000_0113);

    qp2_op(5'd2, NSAMP, CTRL_QUARTER, 32'd0, 32'd24);
    qp2_op(5'd0, START_FREQ, STEP, 32'd1, 32'd64);
    qp2_op(5'd1, 32'd0, 32'd0, 32'd0, 32'd0);

    feed_point(64, 100000, 100000);
    wait_finish;

    check64("TQ4 m3 power", dut.u_peak_finder_wide.max_amplitude, 64'd20000000000);
    qp2_op(5'd10, 32'd0, 32'd0, 32'd0, 32'd0);
    qp2_op(5'd4, 32'd0, 32'd0, 32'd0, 32'd0);
    check32("TQ4 n_used", qtag_dt1_o, 32'd24);
    check32("TQ4 diag word", qtag_dt2_o, 32'h0000_0119);
    qp2_op(5'd11, 32'd0, 32'd0, 32'd0, 32'd0);
    check32("TQ4 mean I", qtag_dt1_o, 32'h0001_86A0);
    check32("TQ4 mean Q", qtag_dt2_o, 32'h0001_86A0);
    qp2_op(5'd12, 32'd0, 32'd0, 32'd0, 32'd0);
    check32("TQ4 log entry 0", qtag_dt1_o, 32'h8000_0119);

    qp2_op(5'd10, 32'd0, 32'd0, 32'd0, 32'd0);

    axi_tbl_write(2'd0, 6'd0, 32'd64, 14'd0, 7'd4);
    axi_tbl_write(2'd0, 6'd1, 32'd32, 14'd0, 7'd4);
    axi_tbl_write(2'd0, 6'd2, 32'd8, 14'd0, 7'd4);
    axi_tbl_write(2'd0, 6'd3, 32'd2, 14'd0, 7'd4);
    axi_tbl_write(2'd1, 6'd0, 32'd100, 14'd0, 7'd4);
    axi_tbl_write(2'd1, 6'd1, 32'd50, 14'd0, 7'd4);
    axi_tbl_write(2'd1, 6'd2, 32'd20, 14'd0, 7'd4);
    axi_tbl_write(2'd1, 6'd3, 32'd10, 14'd0, 7'd4);

    qp2_op(5'd2, NSAMP, CTRL_SHIFT, 32'd0, 32'd0);
    qp2_op(5'd0, START_FREQ, STEP, N_POINTS, 32'd2);
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

    if (errors == 0)
      $display("ALL TESTS PASSED");
    else
      $display("%0d FAILURE(S)", errors);

    $finish;
  end

endmodule
