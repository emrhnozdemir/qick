`timescale 1ns / 1ps

// Directed response-level tests: each accepted probe consumes one averaged
// amplitude response. Frequency acknowledgements and amplitudes are delayed
// independently so movement decisions cannot rely on an immediate response.
module tb_gradient_guard;
  reg clk = 0;
  always #2.5 clk = ~clk;
  reg rst_n = 0;
  reg start_i = 0;
  reg movement_guard_i, two_sided_i, scheduled_i, dip_i;
  reg [31:0] x0_i, f_lo_i, f_hi_i, step_i, min_step_i;
  reg [15:0] max_iteration_i, pair_min_i, pair_max_i;
  reg [7:0] patience_i;
  reg [4:0] lambda_i;
  reg step_lut_write_i = 0;
  reg [31:0] step_lut_data_i = 0;
  wire [31:0] freq_word_o, x_o, signed_sum_high_o;
  wire freq_valid_o, probe_arm_o, busy_o, done_o;
  wire converged_o, capped_o, stalled_o;
  wire [15:0] iteration_o, pairs_o;
  reg freq_ack_i = 0;
  reg amp_valid_i = 0;
  reg [63:0] amp_data_i = 0;

  gradient_engine dut (
    .clk(clk), .rst_n(rst_n), .start_i(start_i),
    .movement_guard_i(movement_guard_i), .two_sided_i(two_sided_i),
    .scheduled_i(scheduled_i), .dip_i(dip_i),
    .x0_i(x0_i), .f_lo_i(f_lo_i), .f_hi_i(f_hi_i),
    .step_i(step_i), .min_step_i(min_step_i),
    .max_iteration_i(max_iteration_i), .patience_i(patience_i),
    .lambda_i(lambda_i), .pair_min_i(pair_min_i), .pair_max_i(pair_max_i),
    .step_lut_write_i(step_lut_write_i), .step_lut_addr_i(6'd0),
    .step_lut_data_i(step_lut_data_i), .step_lut_len_i(7'd1),
    .offset_lut_write_i(1'b0), .offset_lut_addr_i(6'd0),
    .offset_lut_data_i(32'd0), .offset_lut_len_i(7'd1),
    .freq_word_o(freq_word_o), .freq_valid_o(freq_valid_o),
    .freq_ack_i(freq_ack_i), .probe_arm_o(probe_arm_o),
    .amp_valid_i(amp_valid_i), .amp_data_i(amp_data_i),
    .busy_o(busy_o), .done_o(done_o),
    .converged_o(converged_o), .capped_o(capped_o), .stalled_o(stalled_o),
    .x_o(x_o), .iteration_o(iteration_o), .pairs_o(pairs_o),
    .signed_sum_high_o(signed_sum_high_o)
  );

  integer errors = 0;
  integer cases = 0;
  integer mode = 0;
  integer measurements = 0;
  integer arms = 0;
  integer phase = 0;
  integer delay_cycles = 0;
  integer cycles;
  reg active = 0;
  reg [31:0] pending_frequency;
  reg [31:0] trace [0:1023];
  string case_name;

  function automatic [63:0] response_power(input [31:0] frequency, input integer index);
    reg signed [63:0] distance;
    begin
      distance = $signed({1'b0, frequency}) - 64'sd8;
      case (mode)
        0: response_power = {32'd0, frequency} + 64'd100;
        1: response_power = {32'd0, ~frequency} + 64'd100;
        2: response_power = 64'd1000000 - distance * distance;
        3: response_power = 64'd1234;
        4: response_power = 64'd100 + distance * distance;
        // One unresolved iteration, progress, then two unresolved iterations.
        5: response_power = (index == 2 || index == 3)
                            ? {32'd0, frequency} + 64'd100 : 64'd1234;
        default: response_power = 0;
      endcase
    end
  endfunction

  task automatic check(input bit condition, input string description);
    begin
      if (!condition) begin
        $display("FAIL [%s] %s", case_name, description);
        errors = errors + 1;
      end
    end
  endtask

  always @(posedge clk) begin
    if (rst_n && active && probe_arm_o)
      arms = arms + 1;
  end

  always @(negedge clk) begin
    if (!rst_n || !active) begin
      phase = 0;
      freq_ack_i = 0;
      amp_valid_i = 0;
    end else begin
      case (phase)
        0: if (freq_valid_o) begin
          pending_frequency = freq_word_o;
          check(freq_word_o >= f_lo_i && freq_word_o <= f_hi_i,
                "probe must stay inside configured unsigned frequency bounds");
          delay_cycles = 1 + (measurements % 3);
          phase = 1;
        end
        1: begin
          check(freq_valid_o && freq_word_o === pending_frequency,
                "frequency must remain valid and stable during acknowledgement delay");
          if (delay_cycles == 0) begin
            freq_ack_i = 1;
            phase = 2;
          end else delay_cycles = delay_cycles - 1;
        end
        2: begin
          freq_ack_i = 0;
          delay_cycles = 1 + (measurements % 4);
          phase = 3;
        end
        3: if (delay_cycles == 0) begin
          check(measurements < 1024, "probe trace capacity");
          trace[measurements] = pending_frequency;
          amp_data_i = response_power(pending_frequency, measurements);
          amp_valid_i = 1;
          measurements = measurements + 1;
          phase = 4;
        end else delay_cycles = delay_cycles - 1;
        4: begin
          amp_valid_i = 0;
          phase = 0;
        end
      endcase
    end
  end

  task automatic defaults;
    begin
      movement_guard_i = 1;
      two_sided_i = 0;
      scheduled_i = 0;
      dip_i = 0;
      x0_i = 8;
      f_lo_i = 0;
      f_hi_i = 16;
      step_i = 8;
      min_step_i = 2;
      max_iteration_i = 64;
      patience_i = 2;
      lambda_i = 1;
      pair_min_i = 1;
      pair_max_i = 1;
      mode = 0;
    end
  endtask

  task automatic run_case(
    input string name,
    input [31:0] expected_x,
    input integer expected_iterations,
    input integer expected_measurements,
    input bit expected_converged,
    input bit expected_capped,
    input bit expected_stalled,
    input integer expected_pairs
  );
    begin
      case_name = name;
      cases = cases + 1;
      measurements = 0;
      arms = 0;
      @(posedge clk); #1;
      active = 1;
      start_i = 1;
      @(posedge clk); #1;
      start_i = 0;
      check(!converged_o && !capped_o && !stalled_o,
            "start clears all prior completion flags");
      cycles = 0;
      while (!done_o && cycles < 50000) begin
        @(posedge clk); #1;
        cycles = cycles + 1;
      end
      check(done_o, "completion timeout");
      check(!busy_o, "busy must clear at completion");
      check(x_o === expected_x,
            $sformatf("returned frequency expected %0d, got %0d", expected_x, x_o));
      check(iteration_o === expected_iterations[15:0],
            $sformatf("iterations expected %0d, got %0d", expected_iterations, iteration_o));
      check(measurements == expected_measurements,
            $sformatf("measurements expected %0d, got %0d", expected_measurements, measurements));
      check(arms == measurements, "every amplitude has exactly one probe-arm pulse");
      check(converged_o === expected_converged, "converged flag");
      check(capped_o === expected_capped, "capped flag");
      check(stalled_o === expected_stalled, "stalled flag");
      check(pairs_o === expected_pairs[15:0], "last-iteration pair count");
      active = 0;
      repeat (2) @(posedge clk);
      #1;
      check(!done_o, "done is a one-clock pulse");
      $display("CASE %s: x=%0d iterations=%0d measurements=%0d flags=%b%b%b",
               name, x_o, iteration_o, measurements, stalled_o, capped_o, converged_o);
    end
  endtask

  task automatic expect_probe(input integer index, input [31:0] expected_frequency);
    begin
      check(trace[index] === expected_frequency,
            $sformatf("probe %0d expected %0d, got %0d", index, expected_frequency, trace[index]));
    end
  endtask

  initial begin
    defaults();
    repeat (5) @(posedge clk);
    #1 rst_n = 1;
    // A zero scheduled movement tests that the raw guard flag is ignored by
    // scheduled GD, without requiring a populated multi-entry schedule.
    step_lut_data_i = 0;
    step_lut_write_i = 1;
    @(posedge clk); #1 step_lut_write_i = 0;
    repeat (3) @(posedge clk);

    defaults(); x0_i = 16;
    run_case("upper boundary refines then stalls", 16, 4, 8, 0, 0, 1, 1);
    expect_probe(0, 8); expect_probe(2, 12); expect_probe(4, 14); expect_probe(6, 14);

    defaults(); x0_i = 0; mode = 1;
    run_case("lower boundary refines then stalls", 0, 4, 8, 0, 0, 1, 1);
    expect_probe(1, 8); expect_probe(3, 4); expect_probe(5, 2); expect_probe(7, 2);

    defaults(); x0_i = 0; mode = 2;
    run_case("peak reversal halves movement", 8, 8, 16, 0, 0, 1, 1);
    expect_probe(0, 0); expect_probe(1, 8); expect_probe(2, 8); expect_probe(3, 16);
    expect_probe(4, 8); expect_probe(5, 12); expect_probe(6, 4); expect_probe(7, 8);
    expect_probe(8, 4); expect_probe(9, 6); expect_probe(10, 6); expect_probe(11, 8);
    expect_probe(12, 8); expect_probe(13, 10); expect_probe(14, 8); expect_probe(15, 10);

    defaults(); x0_i = 4; step_i = 4; mode = 2;
    run_case("blocked return cycle keeps certified better probe", 8, 5, 10, 0, 0, 1, 1);
    expect_probe(0, 4); expect_probe(1, 8); expect_probe(2, 8); expect_probe(3, 12);
    expect_probe(4, 8); expect_probe(5, 10); expect_probe(6, 6); expect_probe(7, 8);
    expect_probe(8, 6); expect_probe(9, 8);
    check(dut.x === 32'd6, "cycle suppression holds iterate while returning the measured race winner");

    defaults(); x0_i = 0; mode = 4; dip_i = 1;
    run_case("dip reversals use the same guard", 8, 8, 16, 0, 0, 1, 1);

    defaults(); x0_i = 0; step_i = 2; max_iteration_i = 3;
    run_case("certified movement equal to floor continues", 6, 3, 6, 0, 1, 0, 1);
    expect_probe(0, 0); expect_probe(2, 2); expect_probe(4, 4); expect_probe(5, 6);

    defaults(); x0_i = 0; step_i = 1; max_iteration_i = 1;
    run_case("initial movement below floor is raised", 2, 1, 2, 0, 1, 0, 1);
    expect_probe(1, 2);

    defaults(); mode = 3; pair_min_i = 2; pair_max_i = 3;
    run_case("exhausted race refines before patience counts", 8, 4, 24, 0, 0, 1, 3);
    expect_probe(1, 16); expect_probe(7, 12); expect_probe(13, 10); expect_probe(19, 10);

    defaults(); mode = 3; step_i = 3;
    run_case("odd refinement clamps at the floor", 8, 3, 6, 0, 0, 1, 1);
    expect_probe(1, 11); expect_probe(3, 10); expect_probe(5, 10);

    defaults(); x0_i = 0; step_i = 2; mode = 5;
    run_case("accepted progress resets stalled streak", 2, 4, 8, 0, 0, 1, 1);
    expect_probe(0, 0); expect_probe(2, 0); expect_probe(4, 2); expect_probe(6, 2);

    defaults(); x0_i = 7; f_lo_i = 7; f_hi_i = 7;
    run_case("duplicate pair measures singleton once", 7, 1, 1, 0, 0, 1, 0);
    expect_probe(0, 7);

    defaults(); step_i = 2; mode = 1; max_iteration_i = 1;
    run_case("negative cap returns measured incumbent", 8, 1, 2, 0, 1, 0, 1);
    expect_probe(0, 8); expect_probe(1, 10);
    check(dut.x === 32'd6, "negative update is held internally while returned incumbent was measured");

    defaults(); step_i = 2; max_iteration_i = 1;
    run_case("positive cap can return measured second probe", 10, 1, 2, 0, 1, 0, 1);

    defaults(); x0_i = 16; step_i = 0; min_step_i = 0; patience_i = 0;
    run_case("raw zero floor and patience stay bounded", 16, 1, 2, 0, 0, 1, 1);
    expect_probe(0, 15); expect_probe(1, 16);

    defaults(); x0_i = 16; step_i = 2; patience_i = 1; max_iteration_i = 1;
    run_case("stalled reason wins coincident iteration cap", 16, 1, 2, 0, 0, 1, 1);

    defaults(); x0_i = 15; step_i = 4; min_step_i = 2;
    run_case("clipped nonzero movement returns measured better probe", 16, 3, 6, 0, 0, 1, 1);
    expect_probe(0, 15); expect_probe(2, 15); expect_probe(4, 15);
    check(dut.x === 32'd15, "below-floor movement remains suppressed internally");

    defaults(); x0_i = 32'hfffffffe; f_hi_i = 32'hffffffff;
    step_i = 32'hffffffff; min_step_i = 1; max_iteration_i = 1;
    run_case("wide positive step clips without signed wrap", 32'hffffffff, 1, 2, 0, 1, 0, 1);
    expect_probe(0, 32'hfffffffe); expect_probe(1, 32'hffffffff);

    defaults(); x0_i = 1; f_hi_i = 32'hffffffff; mode = 1;
    step_i = 32'hffffffff; min_step_i = 1; max_iteration_i = 1;
    run_case("wide negative step clips without unsigned wrap", 1, 1, 2, 0, 1, 0, 1);
    check(dut.x === 32'd0, "wide negative internal update clips at zero");

    defaults(); x0_i = 0; f_hi_i = 32'hffffffff;
    step_i = 32'hffffffff; min_step_i = 32'hffffffff;
    run_case("full unsigned-span movement equals its floor", 32'hffffffff, 3, 6, 0, 0, 1, 1);
    expect_probe(0, 0); expect_probe(1, 32'hffffffff);

    defaults(); mode = 3; step_i = 2; patience_i = 255; max_iteration_i = 256;
    run_case("maximum patience does not wrap before stopping", 8, 255, 510, 0, 0, 1, 1);

    defaults(); x0_i = 20; f_lo_i = 7; f_hi_i = 7;
    run_case("initial frequency clamp precedes duplicate check", 7, 1, 1, 0, 0, 1, 0);

    defaults(); movement_guard_i = 0; x0_i = 16; max_iteration_i = 3;
    run_case("disabled guard preserves repeated boundary probes", 16, 3, 6, 0, 1, 0, 1);

    defaults(); movement_guard_i = 0; mode = 3;
    run_case("disabled guard preserves legacy tie convergence", 8, 2, 4, 1, 0, 0, 1);

    defaults(); scheduled_i = 1; step_i = 1;
    run_case("raw guard ignored for scheduled GD", 8, 2, 4, 1, 0, 0, 1);

    defaults(); two_sided_i = 1; step_i = 0;
    run_case("raw guard ignored for two-sided KW", 8, 2, 4, 1, 0, 0, 1);

    case_name = "reset";
    @(posedge clk); #1 rst_n = 0;
    repeat (2) @(posedge clk);
    #1;
    check(!busy_o && !done_o && !converged_o && !capped_o && !stalled_o,
          "reset clears busy and completion flags");
    if (errors == 0) begin
      $display("ALL TESTS PASSED: %0d directed gradient movement-guard cases", cases);
      $finish;
    end else begin
      $fatal(1, "%0d gradient movement-guard failures", errors);
    end
  end
endmodule
