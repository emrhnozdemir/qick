`timescale 1ns / 1ps

// Public-interface tests for cumulative N, N+2, ... confirmation.  The
// reported estimate and n_used describe the initial power-of-two candidate;
// later confirming samples are consumed but must not change that estimate.
module tb_short_confirmation;
  reg clk = 0;
  always #1 clk = ~clk;
  reg rst_n = 0;
  reg s_axis_tvalid = 0;
  reg s_axis_tready = 1;
  reg [63:0] s_axis_tdata = 0;
  reg arm_i = 0;
  reg [4:0] avg_shift_i = 6;
  reg [31:0] n_min_i = 4;
  reg estop_en_i = 1;
  reg estop_hold_i = 0;
  reg [15:0] threshold_i = 64;
  reg block_en_i = 0;
  reg [2:0] confirm_i = 3;
  wire warmup_done_o, early_stop_o, early_pulse_o;
  wire [31:0] n_used_o, mean_i_o, mean_q_o;
  wire log_wr_o, power_valid_o;
  wire [9:0] log_entry_o;
  wire [63:0] power_o;

  amplitude_calculator dut (
    .clk(clk), .rst_n(rst_n),
    .s_axis_tvalid(s_axis_tvalid),
    .s_axis_tdata(s_axis_tdata), .arm_i(arm_i), .flush_i(1'b0),
    .avg_shift_i(avg_shift_i), .warmup_shots_i(32'd0), .n_min_i(n_min_i),
    .estop_en_i(estop_en_i), .estop_hold_i(estop_hold_i),
    .threshold_i(threshold_i), .block_en_i(block_en_i), .block_tol_i(32'd0),
    .confirm_i(confirm_i), .short_confirm_i(1'b1),
    .warmup_done_o(warmup_done_o), .early_stop_o(early_stop_o),
    .early_pulse_o(early_pulse_o), .n_used_o(n_used_o),
    .mean_i_o(mean_i_o), .mean_q_o(mean_q_o), .log_wr_o(log_wr_o),
    .log_entry_o(log_entry_o), .power_o(power_o), .power_valid_o(power_valid_o)
  );

  integer errors = 0;
  integer accepted_count = 0;
  integer pulse_count = 0;
  integer power_count = 0;
  integer minimum_confirmation_count = 0;
  integer count_at_pulse = 0;
  reg [31:0] result_n, result_i, result_q;
  reg [63:0] result_power;
  reg result_early;

  // Monitor the external handshake, not implementation-specific counters.
  // Pipeline overshoot is allowed; retiring before confirmation is not.
  always @(posedge clk) begin
    if (!rst_n || arm_i) begin
      accepted_count <= 0;
      pulse_count <= 0;
      power_count <= 0;
      count_at_pulse <= 0;
      result_n <= 0;
      result_i <= 0;
      result_q <= 0;
      result_power <= 0;
      result_early <= 0;
    end else begin
      if (s_axis_tvalid && s_axis_tready)
        accepted_count <= accepted_count + 1;
      if (early_pulse_o) begin
        pulse_count <= pulse_count + 1;
        count_at_pulse <= accepted_count;
        if (accepted_count < minimum_confirmation_count) begin
          $display("FAIL early interrupt after %0d samples, needs at least %0d",
                   accepted_count, minimum_confirmation_count);
          errors = errors + 1;
        end
      end
      if (power_valid_o) begin
        power_count <= power_count + 1;
        result_n <= n_used_o;
        result_i <= mean_i_o;
        result_q <= mean_q_o;
        result_power <= power_o;
        result_early <= early_stop_o;
      end
    end
  end

  task automatic check32(input string name, input [31:0] got,
                          input [31:0] expected);
    if (got !== expected) begin
      $display("FAIL %0s: got %0d (0x%08x), expected %0d (0x%08x)",
               name, $signed(got), got, $signed(expected), expected);
      errors = errors + 1;
    end else
      $display("PASS %0s", name);
  endtask

  task automatic idle(input integer cycles);
    repeat (cycles) @(negedge clk);
  endtask

  task automatic configure(input integer cap_shift, input integer nmin,
                            input integer confirmations, input integer hold,
                            input integer denominator, input integer block_guard,
                            input integer enabled);
    begin
      @(negedge clk);
      s_axis_tvalid = 0;
      s_axis_tready = 1;
      avg_shift_i = cap_shift;
      n_min_i = nmin;
      confirm_i = confirmations;
      estop_hold_i = hold;
      threshold_i = denominator;
      block_en_i = block_guard;
      estop_en_i = enabled;
      minimum_confirmation_count = 0;
      @(negedge clk);
      arm_i = 1;
      @(negedge clk);
      arm_i = 0;
      idle(2);
    end
  endtask

  // gap=0 drives one accepted shot per clock, including across task calls.
  task automatic feed(input integer count, input integer ii, input integer qq,
                       input integer gap);
    integer k;
    begin
      for (k = 0; k < count; k = k + 1) begin
        s_axis_tvalid = 1;
        s_axis_tready = 1;
        s_axis_tdata = {qq[31:0], ii[31:0]};
        @(negedge clk);
        s_axis_tvalid = 0;
        idle(gap);
      end
    end
  endtask

  task automatic no_result(input string name);
    begin
      idle(40);
      check32({name, " no result"}, power_count, 0);
      check32({name, " no interrupt"}, pulse_count, 0);
    end
  endtask

  task automatic expect_result(input string name, input integer n,
                                input integer ii, input integer qq,
                                input integer early, input integer pulses);
    integer timeout;
    reg signed [63:0] wide_i, wide_q;
    reg [63:0] expected_power;
    begin
      timeout = 0;
      while (power_count == 0 && timeout < 1000) begin
        @(negedge clk);
        timeout = timeout + 1;
      end
      if (power_count == 0) begin
        $display("FAIL %0s: result timeout", name);
        errors = errors + 1;
      end else begin
        idle(20);
        check32({name, " one result"}, power_count, 1);
        check32({name, " saved sample count"}, result_n, n);
        check32({name, " saved I mean"}, result_i, ii);
        check32({name, " saved Q mean"}, result_q, qq);
        check32({name, " early flag"}, {31'd0, result_early}, early);
        check32({name, " interrupt count"}, pulse_count, pulses);
        wide_i = ii;
        wide_q = qq;
        expected_power = wide_i * wide_i + wide_q * wide_q;
        if (result_power !== expected_power) begin
          $display("FAIL %0s: power %0d, expected %0d", name,
                   result_power, expected_power);
          errors = errors + 1;
        end else
          $display("PASS %0s power", name);
      end
    end
  endtask

  integer conf;
  initial begin
    idle(8);
    rst_n = 1;
    idle(4);

    // The required policy: pass at 4, 6 and 8, but return the first four.
    configure(6, 4, 3, 0, 64, 0, 1);
    minimum_confirmation_count = 8;
    feed(4, 1000, -500, 24);
    no_result("S0 initial N alone");
    feed(2, 2000, -1000, 24);
    no_result("S0 N+2 alone");
    feed(2, 3000, -1500, 24);
    expect_result("S0 N+4 confirms first N", 4, 1000, -500, 1, 1);
    check32("S0 consumes exactly eight gapped samples", count_at_pulse, 8);

    // Reject the initial N=4 candidate, then qualify a fresh N=8.
    configure(6, 4, 3, 0, 64, 0, 1);
    minimum_confirmation_count = 12;
    feed(1, 1100, 0, 24);
    feed(1, 900, 0, 24);
    feed(4, 1000, 0, 24);
    feed(1, 900, 0, 24);
    feed(1, 1100, 0, 24);
    no_result("S1 N8 candidate needs its own confirmations");
    feed(4, 3000, 0, 24);
    expect_result("S1 first passing candidate N8", 8, 1000, 0, 1, 1);

    // A failed N+2 abandons N=4.  N=8 can start a new sequence.
    configure(6, 4, 3, 0, 64, 0, 1);
    minimum_confirmation_count = 12;
    feed(4, 1000, 0, 24);
    feed(1, 1200, 0, 24);
    feed(1, 800, 0, 24);
    no_result("S2 failed N+2");
    feed(1, 800, 0, 24);
    feed(1, 1200, 0, 24);
    feed(4, 2000, 0, 24);
    expect_result("S2 restart at next power of two", 8, 1000, 0, 1, 1);

    // Failure at N+4=N8 means no restart at the non-power counts 10/12/14.
    configure(6, 4, 3, 0, 64, 0, 1);
    minimum_confirmation_count = 20;
    feed(4, 1000, 0, 24);
    feed(2, 2000, 0, 24);
    feed(1, 2400, 0, 24);
    feed(1, 1600, 0, 24);
    feed(1, 1600, 0, 24);
    feed(1, 2400, 0, 24);
    feed(4, 1000, 0, 24);
    no_result("S3 failed N+4 waits for N16");
    feed(2, 1000, 0, 24);
    feed(4, 3000, 0, 24);
    expect_result("S3 N16 snapshot after failed confirmation", 16, 1375, 0, 1, 1);

    // A signed arithmetic shift must floor the saved mean, including Q.
    configure(6, 4, 3, 0, 64, 0, 1);
    minimum_confirmation_count = 8;
    feed(2, -1000, -1, 24);
    feed(2, -1001, -2, 24);
    feed(4, -3000, -1000, 24);
    expect_result("S4 saved negative fractional means", 4, -1001, -2, 1, 1);

    // At N4: |sum|=256 and |odd-even|=4, so D=64 is exact equality.
    configure(6, 4, 3, 0, 64, 0, 1);
    minimum_confirmation_count = 8;
    feed(1, 65, 0, 24); feed(1, 63, 0, 24);
    feed(1, 65, 0, 24); feed(1, 63, 0, 24);
    feed(4, 64, 0, 24);
    expect_result("S5 threshold equality passes", 4, 64, 0, 1, 1);

    configure(6, 4, 3, 0, 65, 0, 1);
    minimum_confirmation_count = 12;
    feed(1, 65, 0, 24); feed(1, 63, 0, 24);
    feed(1, 65, 0, 24); feed(1, 63, 0, 24);
    feed(4, 64, 0, 24);
    no_result("S6 stricter threshold rejects first candidate");
    feed(4, 64, 0, 24);
    expect_result("S6 threshold just beyond equality", 8, 64, 0, 1, 1);

    // n_min applies to the saved candidate.  Passing checks below n_min
    // cannot be carried forward to qualify an undersized returned estimate.
    configure(6, 5, 3, 0, 64, 0, 1);
    minimum_confirmation_count = 12;
    feed(4, 1000, 0, 24);
    feed(4, 2000, 0, 24);
    no_result("S7 n_min5 rejects saved N4");
    feed(4, 3000, 0, 24);
    expect_result("S7 n_min starts at eligible N8", 8, 1500, 0, 1, 1);

    configure(6, 9, 3, 0, 64, 0, 1);
    minimum_confirmation_count = 20;
    feed(8, 1000, 0, 24);
    feed(4, 2000, 0, 24);
    no_result("S8 n_min9 rejects even confirmed N8");
    feed(4, 2000, 0, 24);
    feed(4, 3000, 0, 24);
    expect_result("S8 n_min starts at eligible N16", 16, 1500, 0, 1, 1);

    // The cap wins when confirmation is incomplete or lands exactly at it.
    configure(2, 4, 3, 0, 64, 0, 1);
    feed(4, 1000, -500, 24);
    expect_result("S9 cap4 fallback", 4, 1000, -500, 0, 0);

    configure(3, 4, 3, 0, 64, 0, 1);
    feed(4, 1000, 0, 24); feed(4, 2000, 0, 24);
    expect_result("S10 cap8 final confirmation at cap", 8, 1500, 0, 0, 0);

    configure(4, 4, 7, 0, 64, 0, 1);
    feed(4, 1000, 0, 24); feed(12, 2000, 0, 24);
    expect_result("S11 cap16 final confirmation at cap", 16, 1750, 0, 0, 0);

    configure(4, 8, 7, 0, 64, 0, 1);
    feed(8, 1000, 0, 24); feed(8, 2000, 0, 24);
    expect_result("S12 cap16 unfinished N8 confirmation", 16, 1500, 0, 0, 0);

    // Confirm counts are TOTAL passes: one candidate plus confirm-1 pairs.
    for (conf = 1; conf <= 7; conf = conf + 1) begin
      if (conf == 1 || conf == 2 || conf == 3 || conf == 7) begin
        configure(6, 4, conf, 0, 64, 0, 1);
        minimum_confirmation_count = 4 + 2 * (conf - 1);
        feed(4, 1000, -500, 24);
        if (conf > 1) begin
          feed(2 * (conf - 2), 3000, -1500, 24);
          no_result($sformatf("S13 confirm%0d before final pair", conf));
          feed(2, 3000, -1500, 24);
        end
        expect_result($sformatf("S13 confirm%0d", conf), 4, 1000, -500, 1, 1);
        check32($sformatf("S13 confirm%0d acquisition count", conf),
                count_at_pulse, 4 + 2 * (conf - 1));
      end
    end

    // Hold freezes the N estimate once confirmed and emits only at the cap.
    configure(5, 4, 3, 1, 64, 0, 1);
    feed(4, 1000, -500, 24); feed(4, 2000, -1000, 24);
    no_result("S14 hold before cap");
    check32("S14 hold already converged", {31'd0, early_stop_o}, 1);
    check32("S14 hold saved N", n_used_o, 4);
    check32("S14 hold frozen I before cap", mean_i_o, 1000);
    feed(24, 100000, -50000, 0);
    expect_result("S14 hold emits original N at cap", 4, 1000, -500, 1, 0);

    // Unsupported short+block mode must fail closed even for stable data.
    configure(4, 4, 3, 0, 64, 1, 1);
    feed(16, 1000, -500, 0);
    expect_result("S15 block guard combination falls back to cap", 16, 1000, -500, 0, 0);

    configure(4, 4, 3, 0, 64, 0, 0);
    feed(16, 1000, -500, 0);
    expect_result("S16 disabled early stop falls back to cap", 16, 1000, -500, 0, 0);

    // Do not count data presented without TVALID (TREADY is tied high at the top).
    configure(6, 4, 3, 0, 64, 0, 1);
    minimum_confirmation_count = 8;
    feed(4, 1000, -500, 24);
    s_axis_tvalid = 0;
    s_axis_tdata = {32'd999999, 32'd999999};
    idle(6);
    idle(6);
    no_result("S17 rejected bus cycles cannot confirm");
    feed(4, 3000, -1500, 24);
    expect_result("S17 accepts only handshaken shots", 4, 1000, -500, 1, 1);
    check32("S17 exactly eight accepted bus shots", accepted_count, 8);

    // Every even count enters the pipeline while the initial verdict is
    // pending.  Later N8/N16 snapshots must not overwrite the saved N4.
    configure(7, 4, 3, 0, 64, 0, 1);
    minimum_confirmation_count = 8;
    feed(4, 1000, -500, 0);
    feed(4, 2000, -1000, 0);
    feed(56, 100000, -50000, 0);
    expect_result("S18 back-to-back N+2/N+4 overlap", 4, 1000, -500, 1, 1);

    configure(7, 4, 7, 0, 64, 0, 1);
    minimum_confirmation_count = 16;
    feed(4, 1000, -500, 0);
    feed(12, 3000, -1500, 0);
    feed(48, 100000, -50000, 0);
    expect_result("S19 continuous seven passes keeps exact N4", 4, 1000, -500, 1, 1);

    // The confirming sample count itself is below the cap, but its verdict
    // can still arrive too late at full input rate.  Retirement uses cap data.
    configure(4, 8, 3, 0, 64, 0, 1);
    minimum_confirmation_count = 12;
    feed(8, 1000, -500, 0);
    feed(8, 2000, -1000, 0);
    expect_result("S19b continuous cap beats in-flight confirmation", 16, 1500, -750, 0, 0);

    // Initial and confirming verdicts from the old acquisition may still
    // be in flight when rearm is issued.  None may retire the new point.
    configure(7, 4, 3, 0, 64, 0, 1);
    feed(8, 1000, -500, 0);
    configure(6, 4, 3, 0, 64, 0, 1);
    no_result("S20 rearm invalidates pending confirmations");
    minimum_confirmation_count = 8;
    feed(4, 2000, -1000, 24);
    no_result("S20 fresh point still needs two confirmations");
    feed(4, 6000, -3000, 24);
    expect_result("S20 rearm returns fresh snapshot", 4, 2000, -1000, 1, 1);

    // Rearm immediately before the final verdict would retire the point.
    // The initial data pipeline is drained; no old point has retired yet.
    configure(7, 4, 3, 0, 64, 0, 1);
    feed(8, 1000, -500, 0);
    idle(5);
    check32("S20b old point has not retired before rearm", {31'd0, dut.stop_check.counter.armed}, 1);
    check32("S20b early_stop still reports the last emitted point (S20)", {31'd0, early_stop_o}, 1);
    configure(6, 4, 3, 0, 64, 0, 1);
    no_result("S20b rearm at final verdict cannot emit stale point");
    minimum_confirmation_count = 8;
    feed(4, 4000, -2000, 24); feed(4, 8000, -4000, 24);
    expect_result("S20b final-verdict rearm returns fresh snapshot", 4, 4000, -2000, 1, 1);

    configure(7, 4, 3, 0, 64, 0, 1);
    feed(8, 1000, -500, 0);
    rst_n = 0;
    idle(4);
    rst_n = 1;
    configure(6, 4, 3, 0, 64, 0, 1);
    no_result("S21 reset invalidates pending confirmations");
    minimum_confirmation_count = 8;
    feed(4, -2000, 1000, 24); feed(4, -6000, 3000, 24);
    expect_result("S21 reset returns fresh snapshot", 4, -2000, 1000, 1, 1);

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
