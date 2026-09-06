`timescale 1ns / 1ps

module tb_amplitude_calculator;

  localparam CLKP = 2;

  reg clk = 1'b0;
  reg rst_n;

  always #(CLKP / 2) clk = ~clk;

  reg s_axis_tvalid;
  reg s_axis_tready;
  reg [63:0] s_axis_tdata;

  reg arm_i;
  reg [4:0] avg_shift_i;
  reg [31:0] warmup_shots_i;
  reg [31:0] n_min_i;

  reg estop_en_i;
  reg estop_hold_i;
  reg [15:0] threshold_i;
  reg block_en_i = 0;
  reg [31:0] block_tol_i = 0;
  reg [2:0] confirm_i;

  wire warmup_done_o;
  wire early_stop_o;
  wire early_pulse_o;
  wire [31:0] n_used_o;
  wire [31:0] mean_i_o;
  wire [31:0] mean_q_o;
  wire log_wr_o;
  wire [15:0] log_entry_o;
  wire [63:0] power_o;
  wire power_valid_o;

  integer errors = 0;

  amplitude_calculator dut (
    .clk              (clk),
    .rst_n            (rst_n),
    .s_axis_tvalid    (s_axis_tvalid),
    .s_axis_tready    (s_axis_tready),
    .s_axis_tdata     (s_axis_tdata),
    .arm_i            (arm_i),
    .avg_shift_i      (avg_shift_i),
    .warmup_shots_i             (warmup_shots_i),
    .n_min_i          (n_min_i),
    .estop_en_i       (estop_en_i),
    .estop_hold_i     (estop_hold_i),
    .threshold_i      (threshold_i),
    .block_en_i       (block_en_i),
    .block_tol_i      (block_tol_i),
    .confirm_i        (confirm_i),
    .warmup_done_o    (warmup_done_o),
    .early_stop_o     (early_stop_o),
    .early_pulse_o    (early_pulse_o),
    .n_used_o         (n_used_o),
    .mean_i_o         (mean_i_o),
    .mean_q_o         (mean_q_o),
    .log_wr_o         (log_wr_o),
    .log_entry_o      (log_entry_o),
    .power_o          (power_o),
    .power_valid_o    (power_valid_o)
  );

  reg [15:0] log_seen;
  reg early_pulse_seen;
  reg [63:0] power_seen;
  reg power_hit;

  always @(posedge clk) begin
    if (!rst_n) begin
      log_seen <= 16'hFFFF;
      early_pulse_seen <= 1'b0;
      power_seen <= {64{1'b0}};
      power_hit <= 1'b0;
    end else begin
      if (log_wr_o)
        log_seen <= log_entry_o;
      else
        log_seen <= log_seen;

      if (arm_i)
        early_pulse_seen <= 1'b0;
      else if (early_pulse_o)
        early_pulse_seen <= 1'b1;
      else
        early_pulse_seen <= early_pulse_seen;

      if (arm_i) begin
        power_seen <= power_seen;
        power_hit <= 1'b0;
      end else if (power_valid_o) begin
        power_seen <= power_o;
        power_hit <= 1'b1;
      end else begin
        power_seen <= power_seen;
        power_hit <= power_hit;
      end
    end
  end

  task automatic chk32(input string name, input [31:0] got, input [31:0] exp);
    begin
      if (got !== exp) begin
        $display("FAIL %0s: got %0d (0x%08x), expected %0d (0x%08x)",
                 name, $signed(got), got, $signed(exp), exp);
        errors = errors + 1;
      end else begin
        $display("PASS %0s = %0d (0x%08x)", name, $signed(got), got);
      end
    end
  endtask

  task automatic chk64(input string name, input [63:0] got, input [63:0] exp);
    begin
      if (got !== exp) begin
        $display("FAIL %0s: got %0d (0x%016x), expected %0d (0x%016x)",
                 name, got, got, exp, exp);
        errors = errors + 1;
      end else begin
        $display("PASS %0s = %0d (0x%016x)", name, got, got);
      end
    end
  endtask

  task automatic cfg(input integer avg_sh, input integer en, input integer hold,
                     input integer nmin, input integer conf, input integer d);
    begin
      @(posedge clk);
      avg_shift_i <= avg_sh[4:0];
      estop_en_i <= en[0];
      estop_hold_i <= hold[0];
      n_min_i <= nmin[31:0];
      confirm_i <= conf[2:0];
      threshold_i <= d[15:0];
      @(posedge clk);
    end
  endtask

  task automatic do_arm;
    begin
      @(posedge clk);
      arm_i <= 1'b1;
      @(posedge clk);
      arm_i <= 1'b0;
      @(posedge clk);
    end
  endtask

  task automatic feed(input integer ii, input integer qq, input integer gap);
    integer g;
    begin
      @(posedge clk);
      s_axis_tvalid <= 1'b1;
      s_axis_tdata <= {qq[31:0], ii[31:0]};
      @(posedge clk);
      s_axis_tvalid <= 1'b0;
      for (g = 0; g < gap; g = g + 1)
        @(posedge clk);
    end
  endtask

  task automatic feed_n(input integer n, input integer ii, input integer qq,
                        input integer gap);
    integer k;
    begin
      for (k = 0; k < n; k = k + 1)
        feed(ii, qq, gap);
    end
  endtask

  task automatic feed_overlapping_checkpoints;
    integer k;
    integer ii;
    integer qq;
    begin
      for (k = 0; k < 64; k = k + 1) begin
        ii = (k < 4) ? 1000 : 100000;
        qq = (k < 4) ? -500 : -50000;
        @(posedge clk);
        s_axis_tvalid <= 1'b1;
        s_axis_tdata <= {qq[31:0], ii[31:0]};
      end
      @(posedge clk);
      s_axis_tvalid <= 1'b0;
    end
  endtask

  task automatic feed_continuous(input integer n, input integer ii, input integer qq);
    integer k;
    begin
      for (k = 0; k < n; k = k + 1) begin
        @(posedge clk);
        s_axis_tvalid <= 1;
        s_axis_tdata <= {qq[31:0], ii[31:0]};
      end
      @(posedge clk);
      s_axis_tvalid <= 0;
    end
  endtask

  task automatic wait_power(input string name);
    integer g;
    begin
      g = 0;
      while (!power_hit && (g < 4000)) begin
        @(posedge clk);
        g = g + 1;
      end
      if (g >= 4000) begin
        $display("FAIL %0s: power_valid_o timeout", name);
        errors = errors + 1;
      end else begin
        $display("PASS %0s power_valid_o", name);
      end
    end
  endtask

  initial begin
    rst_n = 1'b0;
    s_axis_tvalid = 1'b0;
    s_axis_tready = 1'b1;
    s_axis_tdata = 64'd0;
    arm_i = 1'b0;
    avg_shift_i = 5'd0;
    warmup_shots_i = 32'd0;
    n_min_i = 32'd0;
    estop_en_i = 1'b0;
    estop_hold_i = 1'b0;
    threshold_i = 16'd64;
    confirm_i = 3'd1;

    repeat (10) @(posedge clk);
    rst_n = 1'b1;
    repeat (5) @(posedge clk);

    // ---------------------------------------------------------------
    // A0  cap retirement, exact power-of-two divide, signed Q
    // ---------------------------------------------------------------
    cfg(3, 0, 0, 0, 1, 64);
    do_arm;
    feed_n(8, 1000, -500, 3);
    wait_power("A0");
    chk32("A0 mean I", mean_i_o, 32'sd1000);
    chk32("A0 mean Q", mean_q_o, -32'sd500);
    chk64("A0 power", power_seen, 64'd1250000);
    chk32("A0 n_used", n_used_o, 32'd8);
    chk32("A0 early_stop", {31'd0, early_stop_o}, 32'd0);
    chk32("A0 log entry (cap)", {16'd0, log_seen}, 32'h0000_0004);

    // ---------------------------------------------------------------
    // A1  truncating shift, positive: 1+1+2+2 = 6, 6/4 = 1.5 -> 1
    // ---------------------------------------------------------------
    cfg(2, 0, 0, 0, 1, 64);
    do_arm;
    feed(1, 0, 3);
    feed(1, 0, 3);
    feed(2, 0, 3);
    feed(2, 0, 3);
    wait_power("A1");
    chk32("A1 mean I (trunc +1.5 -> 1)", mean_i_o, 32'sd1);
    chk64("A1 power", power_seen, 64'd1);

    // ---------------------------------------------------------------
    // A1b arithmetic shift floors toward -INF, unlike round-half-up:
    //     -6/4 = -1.5 -> -2
    // ---------------------------------------------------------------
    cfg(2, 0, 0, 0, 1, 64);
    do_arm;
    feed(-1, 0, 3);
    feed(-1, 0, 3);
    feed(-2, 0, 3);
    feed(-2, 0, 3);
    wait_power("A1b");
    chk32("A1b mean I (trunc -1.5 -> -2)", mean_i_o, -32'sd2);
    chk64("A1b power", power_seen, 64'd4);

    // ---------------------------------------------------------------
    // A2  early stop at the first checkpoint (n = 4, j = 2).
    //     A constant input makes the alternating accumulator zero at
    //     every even n, so the split test passes immediately.
    //     The shift must come from j, NOT from flog2(avg).
    // ---------------------------------------------------------------
    cfg(6, 1, 0, 4, 1, 64);
    do_arm;
    feed_n(8, 1000, 0, 3);
    wait_power("A2");
    chk32("A2 mean I (>>j, not >>flog2(64))", mean_i_o, 32'sd1000);
    chk32("A2 n_used", n_used_o, 32'd4);
    chk32("A2 early_stop", {31'd0, early_stop_o}, 32'd1);
    chk32("A2 early_pulse fired", {31'd0, early_pulse_seen}, 32'd1);
    chk64("A2 power", power_seen, 64'd1000000);
    chk32("A2 log entry (stop, k=2)", {16'd0, log_seen}, 32'h0000_0110);

    // ---------------------------------------------------------------
    // A3  drain / hold: stop at n = 4, keep counting to the cap, and
    //     the frozen value must survive shots that would wreck it
    // ---------------------------------------------------------------
    cfg(4, 1, 1, 4, 1, 64);
    do_arm;
    feed_n(4, 1000, 0, 3);
    feed_n(12, 100000, 0, 3);
    wait_power("A3");
    chk32("A3 mean I frozen at stop", mean_i_o, 32'sd1000);
    chk32("A3 n_used", n_used_o, 32'd4);
    chk32("A3 early_stop", {31'd0, early_stop_o}, 32'd1);
    chk32("A3 early_pulse suppressed by hold", {31'd0, early_pulse_seen}, 32'd0);
    chk64("A3 power", power_seen, 64'd1000000);

    // ---------------------------------------------------------------
    // A4  estop_en = 0 must ignore a would-be stop and run to the cap
    // ---------------------------------------------------------------
    cfg(3, 0, 0, 4, 1, 64);
    do_arm;
    feed_n(8, 1000, 0, 3);
    wait_power("A4");
    chk32("A4 n_used (ran to cap)", n_used_o, 32'd8);
    chk32("A4 early_stop", {31'd0, early_stop_o}, 32'd0);
    chk32("A4 mean I", mean_i_o, 32'sd1000);

    // ---------------------------------------------------------------
    // A5  int32 rails: the squarer must stay signed-correct at -2^31
    // ---------------------------------------------------------------
    cfg(0, 0, 0, 0, 1, 64);
    do_arm;
    feed(32'h7FFF_FFFF, 32'h8000_0000, 3);
    wait_power("A5");
    chk32("A5 mean I rail", mean_i_o, 32'h7FFF_FFFF);
    chk32("A5 mean Q rail", mean_q_o, 32'h8000_0000);
    chk64("A5 power at rails", power_seen, 64'h7FFF_FFFF_0000_0001);

    // ---------------------------------------------------------------
    // A6  re-arm must clear the accumulator
    // ---------------------------------------------------------------
    cfg(2, 0, 0, 0, 1, 64);
    do_arm;
    feed_n(4, 100, 0, 3);
    wait_power("A6");
    chk32("A6 mean I after re-arm", mean_i_o, 32'sd100);
    chk64("A6 power", power_seen, 64'd10000);

    // ---------------------------------------------------------------
    // A7  warmup_done tracks n0
    // ---------------------------------------------------------------
    warmup_shots_i = 32'd3;
    cfg(3, 0, 0, 0, 1, 64);
    do_arm;
    chk32("A7 warmup_done low at arm", {31'd0, warmup_done_o}, 32'd0);
    feed_n(3, 10, 0, 3);
    chk32("A7 warmup_done high after n0", {31'd0, warmup_done_o}, 32'd1);
    feed_n(5, 10, 0, 3);
    wait_power("A7");
    warmup_shots_i = 32'd0;

    // ---------------------------------------------------------------
    // A8  rails at a REAL cap: 256 shots at the int32 rails makes the
    //     accumulator carry a 40-bit sum, so this exercises the wide
    //     path that A5 (cap = 1 shot) never touches.  The mean and the
    //     power must come back identical to A5.
    // ---------------------------------------------------------------
    cfg(8, 0, 0, 0, 1, 64);
    do_arm;
    feed_n(256, 32'h7FFF_FFFF, 32'h8000_0000, 1);
    wait_power("A8");
    chk32("A8 mean I rail over 256 shots", mean_i_o, 32'h7FFF_FFFF);
    chk32("A8 mean Q rail over 256 shots", mean_q_o, 32'h8000_0000);
    chk64("A8 power at rails over 256 shots", power_seen, 64'h7FFF_FFFF_0000_0001);

    // ---------------------------------------------------------------
    // A9  the accumulators are 58 bit, sized for a 2^26 cap.  avg_shift
    //     is 5 bits so software CAN ask for 2^31; the counter must clamp
    //     it to 26 or the accumulator would silently overflow.
    // ---------------------------------------------------------------
    cfg(31, 0, 0, 0, 1, 64);
    do_arm;
    chk32("A9 avg_shift 31 clamped to 26",
          {27'd0, dut.stop_check.counter.cap_exponent}, 32'd26);
    cfg(8, 0, 0, 0, 1, 64);
    do_arm;
    chk32("A9 avg_shift 8 passes through",
          {27'd0, dut.stop_check.counter.cap_exponent}, 32'd8);

    cfg(6, 1, 0, 4, 1, 64);
    do_arm;
    feed_overlapping_checkpoints;
    wait_power("A10");
    chk32("A10 overlapping checkpoint mean I", mean_i_o, 32'sd1000);
    chk32("A10 overlapping checkpoint mean Q", mean_q_o, -32'sd500);
    chk32("A10 overlapping checkpoint n_used", n_used_o, 32'd4);
    chk64("A10 overlapping checkpoint power", power_seen, 64'd1250000);

    cfg(6, 1, 1, 4, 1, 64);
    do_arm;
    feed_overlapping_checkpoints;
    wait_power("A11");
    chk32("A11 overlapping checkpoint hold mean I", mean_i_o, 32'sd1000);
    chk32("A11 overlapping checkpoint hold mean Q", mean_q_o, -32'sd500);
    chk32("A11 overlapping checkpoint hold n_used", n_used_o, 32'd4);
    chk32("A11 hold suppresses interrupt", {31'd0, early_pulse_seen}, 32'd0);
    chk64("A11 overlapping checkpoint hold power", power_seen, 64'd1250000);

    block_en_i = 1;
    block_tol_i = 0;
    cfg(6, 1, 0, 4, 1, 64);
    do_arm;
    feed_continuous(64, 1000, -500);
    wait_power("A12");
    chk32("A12 first complete block checkpoint", n_used_o, 8);
    chk32("A12 signed stable mean I", mean_i_o, 1000);
    chk32("A12 signed stable mean Q", mean_q_o, -500);
    chk32("A12 early interrupt", {31'd0, early_pulse_seen}, 1);

    cfg(6, 1, 0, 4, 1, 64);
    do_arm;
    feed_overlapping_checkpoints;
    wait_power("A13");
    chk32("A13 step drift reaches cap", n_used_o, 64);
    chk32("A13 step drift is not converged", {31'd0, early_stop_o}, 0);
    chk32("A13 block failure does not mark odd/even saturation", {31'd0, log_seen[9]}, 0);
    chk32("A13 cap mean I", mean_i_o, 93812);
    chk32("A13 cap mean Q floors negative average", mean_q_o, -46907);

    block_tol_i = 30;
    cfg(6, 1, 0, 4, 1, 64);
    do_arm;
    feed_n(4, 1000, -500, 3);
    feed_n(60, 1010, -480, 3);
    wait_power("A14");
    chk32("A14 tolerance equality passes at8", n_used_o, 8);
    chk32("A14 mean I", mean_i_o, 1005);
    chk32("A14 mean Q", mean_q_o, -490);

    block_tol_i = 29;
    cfg(6, 1, 0, 4, 1, 64);
    do_arm;
    feed_n(4, 1000, -500, 3);
    feed_n(60, 1010, -480, 3);
    wait_power("A15");
    chk32("A15 tolerance one lower rejects8 and passes16", n_used_o, 16);
    chk32("A15 mean I", mean_i_o, 1007);
    chk32("A15 mean Q", mean_q_o, -485);

    block_tol_i = 0;
    cfg(6, 1, 0, 4, 1, 64);
    do_arm;
    feed_continuous(64, 32'h8000_0000, 32'h8000_0000);
    wait_power("A16");
    chk32("A16 signed minimum stable block", n_used_o, 8);
    chk64("A16 signed minimum power", power_seen, 64'h8000_0000_0000_0000);

    cfg(6, 1, 0, 4, 2, 64);
    do_arm;
    feed_continuous(64, 0, 0);
    wait_power("A17");
    chk32("A17 confirmation needs complete checkpoints8 and16", n_used_o, 16);
    chk64("A17 exactly zero remains stable", power_seen, 0);

    block_tol_i = 32'hffff_ffff;
    cfg(6, 1, 0, 4, 1, 64);
    do_arm;
    chk32("A18 arm invalidates both snapshot epochs", {30'd0, dut.stop_check.magnitude.snapshot_valid}, 0);
    feed_n(4, 1234, -4321, 3);
    repeat (12) @(posedge clk);
    chk32("A18 no retirement without midpoint baseline", {31'd0, power_hit}, 0);
    feed_n(4, 1234, -4321, 3);
    wait_power("A18");
    chk32("A18 fresh baseline permits8", n_used_o, 8);

    block_tol_i = 0;
    cfg(6, 1, 1, 4, 1, 64);
    do_arm;
    feed_continuous(8, 1000, -500);
    feed_continuous(56, 100000, -50000);
    wait_power("A19");
    chk32("A19 hold keeps accepted8 snapshot through cap", n_used_o, 8);
    chk32("A19 hold mean I", mean_i_o, 1000);
    chk32("A19 hold mean Q", mean_q_o, -500);
    chk32("A19 hold suppresses interrupt", {31'd0, early_pulse_seen}, 0);

    cfg(3, 1, 0, 4, 1, 64);
    do_arm;
    feed_n(8, 1000, 0, 3);
    wait_power("A20");
    chk32("A20 cap8 has no earlier complete block test", {31'd0, early_stop_o}, 0);
    chk32("A20 cap8 shot count", n_used_o, 8);

    cfg(5, 0, 0, 4, 1, 64);
    do_arm;
    feed_continuous(32, 1000, -500);
    wait_power("A21");
    chk32("A21 disabled early stopping ignores block guard", n_used_o, 32);
    chk32("A21 disabled early stopping emits no interrupt", {31'd0, early_pulse_seen}, 0);

    block_tol_i = 32'hffff_ffff;
    cfg(6, 1, 0, 4, 1, 64);
    do_arm;
    feed_n(4, 32'h8000_0000, 0, 3);
    feed_n(60, 32'h7fff_ffff, 0, 3);
    wait_power("A22");
    chk32("A22 full-width tolerance accepts one-channel rail difference", n_used_o, 8);
    chk32("A22 symmetric rails preserve negative rounding", mean_i_o, -1);

    cfg(6, 1, 0, 4, 1, 64);
    do_arm;
    feed_n(4, 32'h8000_0000, 32'h8000_0000, 3);
    feed_n(60, 32'h7fff_ffff, 32'h7fff_ffff, 3);
    wait_power("A23");
    chk32("A23 two-channel L1 rejects8 and accepts16", n_used_o, 16);
    chk32("A23 rail mean I", mean_i_o, 32'h3fff_ffff);
    chk32("A23 rail mean Q", mean_q_o, 32'h3fff_ffff);

    repeat (20) @(posedge clk);

    if (errors == 0)
      $display("ALL TESTS PASSED");
    else
      $fatal(1, "%0d FAILURE(S)", errors);

    $finish;
  end

  initial begin
    #2000000;
    $fatal(1, "FAIL: global timeout");
  end

endmodule
