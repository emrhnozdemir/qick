`timescale 1ns / 1ps

module gradient_engine (
  input clk,
  input rst_n,

  input start_i,
  input two_sided_i,
  input scheduled_i,
  input dip_i,
  input [31:0] x0_i,
  input [31:0] f_lo_i,
  input [31:0] f_hi_i,
  input [31:0] step_i,
  input [31:0] min_step_i,
  input [15:0] max_iteration_i,
  input [7:0] patience_i,
  input [4:0] lambda_i,
  input [15:0] pair_min_i,
  input [15:0] pair_max_i,

  input step_lut_write_i,
  input [5:0] step_lut_addr_i,
  input [31:0] step_lut_data_i,
  input [6:0] step_lut_len_i,
  input offset_lut_write_i,
  input [5:0] offset_lut_addr_i,
  input [31:0] offset_lut_data_i,
  input [6:0] offset_lut_len_i,

  (* MARK_DEBUG = "TRUE" *) output reg [31:0] freq_word_o,
  (* MARK_DEBUG = "TRUE" *) output reg freq_valid_o,
  input freq_ack_i,
  (* MARK_DEBUG = "TRUE" *) output reg probe_arm_o,
  input amp_valid_i,
  input [63:0] amp_data_i,

  (* MARK_DEBUG = "TRUE" *) output reg busy_o,
  (* MARK_DEBUG = "TRUE" *) output reg done_o,
  (* MARK_DEBUG = "TRUE" *) output reg converged_o,
  (* MARK_DEBUG = "TRUE" *) output reg capped_o,
  output [31:0] x_o,
  output [15:0] iteration_o,
  output [15:0] pairs_o,
  output [31:0] signed_sum_high_o
);

  localparam [3:0] S_IDLE = 4'd0, S_PAIR_INIT = 4'd1, S_PRESENT_A = 4'd2, S_MEASURE_A = 4'd3, S_PRESENT_B = 4'd4, S_MEASURE_B = 4'd5, S_DECIDE = 4'd6, S_STEP = 4'd7, S_TIE = 4'd8, S_CONVERGE = 4'd9, S_DONE = 4'd10, S_DIFFERENCE = 4'd11, S_CERTIFY = 4'd12;

  (* MARK_DEBUG = "TRUE" *) reg [3:0] state;
  reg [3:0] next_state;

  (* MARK_DEBUG = "TRUE" *) reg two_sided;
  (* MARK_DEBUG = "TRUE" *) reg scheduled;
  (* MARK_DEBUG = "TRUE" *) reg dip;
  (* MARK_DEBUG = "TRUE" *) reg [31:0] f_lo;
  (* MARK_DEBUG = "TRUE" *) reg [31:0] f_hi;
  (* MARK_DEBUG = "TRUE" *) reg [31:0] step;
  (* MARK_DEBUG = "TRUE" *) reg [31:0] min_step;
  (* MARK_DEBUG = "TRUE" *) reg [15:0] max_iteration;
  (* MARK_DEBUG = "TRUE" *) reg [15:0] pair_min;
  (* MARK_DEBUG = "TRUE" *) reg [15:0] pair_max;
  (* MARK_DEBUG = "TRUE" *) reg [7:0] patience;
  (* MARK_DEBUG = "TRUE" *) reg [4:0] lambda;

  (* MARK_DEBUG = "TRUE" *) reg [31:0] x;
  (* MARK_DEBUG = "TRUE" *) reg [63:0] power_a;
  (* MARK_DEBUG = "TRUE" *) reg [63:0] power_b;

  wire [31:0] initial_x;
  range_clip #(.W(32)) seed_clamp(
    .a_i(x0_i),
    .lo_i(f_lo_i),
    .hi_i(f_hi_i),
    .is_signed_i(1'b0),
    .y_o(initial_x)
  );

  assign x_o = x;

  wire [15:0] iteration;
  wire [15:0] pair_count;

  wire iteration_clear = (state == S_IDLE) & start_i;
  wire iteration_enable = (state == S_STEP) | (state == S_TIE);
  wire pair_clear = (state == S_PAIR_INIT);
  wire pair_enable = (state == S_CERTIFY);

  event_counter #(.W(16)) iterations(
    .clk(clk),
    .rst_n(rst_n),
    .clr(iteration_clear),
    .en(iteration_enable),
    .q_o(iteration)
  );

  event_counter #(.W(16)) pairs(
    .clk(clk),
    .rst_n(rst_n),
    .clr(pair_clear),
    .en(pair_enable),
    .q_o(pair_count)
  );

  assign iteration_o = iteration;
  assign pairs_o = pair_count;

  wire [31:0] scheduled_step;
  wire [31:0] scheduled_offset;

  wire [6:0] step_length = (step_lut_len_i == 7'd0) ? 7'd1 : step_lut_len_i;
  wire [6:0] step_last = step_length - 7'd1;
  wire [5:0] step_address = (iteration >= {9'd0, step_length}) ? step_last[5:0] : iteration[5:0];

  wire [6:0] offset_length = (offset_lut_len_i == 7'd0) ? 7'd1 : offset_lut_len_i;
  wire [6:0] offset_last = offset_length - 7'd1;
  wire [5:0] offset_address = (iteration >= {9'd0, offset_length}) ? offset_last[5:0] : iteration[5:0];

  bram_sched_lut step_schedule(
    .clka(clk),
    .wea(step_lut_write_i),
    .addra(step_lut_addr_i),
    .dina(step_lut_data_i),
    .clkb(clk),
    .addrb(step_address),
    .doutb(scheduled_step)
  );

  bram_sched_lut offset_schedule(
    .clka(clk),
    .wea(offset_lut_write_i),
    .addra(offset_lut_addr_i),
    .dina(offset_lut_data_i),
    .clkb(clk),
    .addrb(offset_address),
    .doutb(scheduled_offset)
  );

  wire [31:0] step_size = scheduled ? scheduled_step : step;
  wire [31:0] probe_offset = two_sided ? (scheduled ? scheduled_offset : step) : step;

  wire [31:0] probe_high;
  wire [31:0] probe_low;

  probe_generator probes(
    .x_i(x),
    .c_i(probe_offset),
    .f_lo_i(f_lo),
    .f_hi_i(f_hi),
    .x_plus_o(probe_high),
    .x_minus_o(probe_low)
  );

  wire [31:0] probe_first = (two_sided | (probe_high == x)) ? probe_low : x;
  wire [31:0] probe_second = probe_high;

  wire signed [64:0] power_delta;
  wire [64:0] power_delta_magnitude;
  wire delta_positive;
  wire delta_negative;

  probe_difference differ(
    .p_a_i(power_a),
    .p_b_i(power_b),
    .dip_i(dip),
    .dp_o(power_delta),
    .dp_abs_o(power_delta_magnitude),
    .pos_o(delta_positive),
    .neg_o(delta_negative)
  );

  (* MARK_DEBUG = "TRUE" *) reg signed [64:0] held_delta;
  (* MARK_DEBUG = "TRUE" *) reg [64:0] held_magnitude;
  (* MARK_DEBUG = "TRUE" *) reg held_positive;
  (* MARK_DEBUG = "TRUE" *) reg held_negative;

  always @(posedge clk) begin
    if (!rst_n) begin
      held_delta <= 0;
      held_magnitude <= 0;
      held_positive <= 0;
      held_negative <= 0;
    end else if (state == S_DIFFERENCE) begin
      held_delta <= power_delta;
      held_magnitude <= power_delta_magnitude;
      held_positive <= delta_positive;
      held_negative <= delta_negative;
    end
  end

  wire race_clear = (state == S_PAIR_INIT);
  wire race_enable = (state == S_CERTIFY);

  wire signed [72:0] signed_sum;
  wire signed [72:0] signed_sum_next;
  wire signed [72:0] magnitude_sum_next;

  signed_accumulator #(.W(73)) signed_race(
    .clk(clk),
    .rst_n(rst_n),
    .clr(race_clear),
    .en(race_enable),
    .d_i({{8{held_delta[64]}}, held_delta}),
    .q_o(signed_sum),
    .q_nxt_o(signed_sum_next)
  );

  signed_accumulator #(.W(73)) magnitude_race(
    .clk(clk),
    .rst_n(rst_n),
    .clr(race_clear),
    .en(race_enable),
    .d_i({8'd0, held_magnitude}),
    .q_o(),
    .q_nxt_o(magnitude_sum_next)
  );

  assign signed_sum_high_o = signed_sum[72:41];

  wire [72:0] signed_sum_magnitude;

  abs_value #(.W(73)) signed_race_magnitude(
    .a_i(signed_sum_next),
    .y_o(signed_sum_magnitude)
  );

  wire [72:0] magnitude_sum_scaled = magnitude_sum_next >> lambda;

  (* MARK_DEBUG = "TRUE" *) reg [72:0] held_signed_magnitude;
  (* MARK_DEBUG = "TRUE" *) reg [72:0] held_magnitude_scaled;

  always @(posedge clk) begin
    if (!rst_n) begin
      held_signed_magnitude <= 0;
      held_magnitude_scaled <= 0;
    end else if (state == S_CERTIFY) begin
      held_signed_magnitude <= signed_sum_magnitude;
      held_magnitude_scaled <= magnitude_sum_scaled;
    end
  end

  wire certified = (held_signed_magnitude > held_magnitude_scaled) & (pair_count >= pair_min);
  wire race_exhausted = (pair_count >= pair_max);

  wire signed [33:0] step_delta;
  wire step_positive = scheduled ? held_positive : (~signed_sum[72] & (signed_sum != 0));
  wire step_negative = scheduled ? held_negative : signed_sum[72];

  signed_step #(.W(34)) stepper(
    .pos_i(step_positive),
    .neg_i(step_negative),
    .step_i({2'b00, step_size}),
    .delta_o(step_delta)
  );

  wire [33:0] next_x;

  range_clip #(.W(34)) clamp(
    .a_i({2'b00, x} + step_delta),
    .lo_i({2'b00, f_lo}),
    .hi_i({2'b00, f_hi}),
    .is_signed_i(1'b1),
    .y_o(next_x)
  );

  wire step_below_min = (step_size < min_step);

  wire patience_clear = (state == S_IDLE) & start_i;
  wire patience_step = (state == S_STEP) | (state == S_TIE);
  wire patience_hit = (state == S_TIE) ? 1'b1 : (scheduled & step_below_min);
  wire patience_converged;

  convergence_patience #(.W(8)) patience_check(
    .clk(clk),
    .rst_n(rst_n),
    .clr(patience_clear),
    .step_i(patience_step),
    .hit_i(patience_hit),
    .patience_i(patience),
    .conv_o(patience_converged)
  );

  always @(posedge clk) begin
    if (!rst_n)
      state <= S_IDLE;
    else
      state <= next_state;
  end

  always @(*) begin
    case (state)
      S_IDLE:
        next_state = start_i ? S_PAIR_INIT : S_IDLE;

      S_PAIR_INIT:
        next_state = S_PRESENT_A;

      S_PRESENT_A:
        next_state = freq_ack_i ? S_MEASURE_A : S_PRESENT_A;

      S_MEASURE_A:
        next_state = amp_valid_i ? S_PRESENT_B : S_MEASURE_A;

      S_PRESENT_B:
        next_state = freq_ack_i ? S_MEASURE_B : S_PRESENT_B;

      S_MEASURE_B:
        next_state = amp_valid_i ? S_DIFFERENCE : S_MEASURE_B;

      S_DIFFERENCE:
        next_state = S_CERTIFY;

      S_CERTIFY:
        next_state = S_DECIDE;

      S_DECIDE: begin
        if (scheduled)
          next_state = S_STEP;
        else if (certified)
          next_state = S_STEP;
        else if (race_exhausted)
          next_state = S_TIE;
        else
          next_state = S_PRESENT_A;
      end

      S_STEP:
        next_state = S_CONVERGE;

      S_TIE:
        next_state = S_CONVERGE;

      S_CONVERGE: begin
        if (patience_converged)
          next_state = S_DONE;
        else if (iteration >= max_iteration)
          next_state = S_DONE;
        else
          next_state = S_PAIR_INIT;
      end

      S_DONE:
        next_state = S_IDLE;

      default:
        next_state = S_IDLE;
    endcase
  end

  always @(posedge clk) begin
    if (!rst_n) begin
      two_sided <= 0;
      scheduled <= 0;
      dip <= 0;
      f_lo <= 0;
      f_hi <= 32'hFFFFFFFF;
      step <= 0;
      min_step <= 0;
      max_iteration <= 0;
      pair_min <= 1;
      pair_max <= 1;
      patience <= 0;
      lambda <= 0;
    end else if ((state == S_IDLE) & start_i) begin
      two_sided <= two_sided_i;
      scheduled <= scheduled_i;
      dip <= dip_i;
      f_lo <= f_lo_i;
      f_hi <= f_hi_i;
      step <= step_i;
      min_step <= min_step_i;
      max_iteration <= (max_iteration_i == 16'd0) ? 16'd1 : max_iteration_i;
      pair_min <= (pair_min_i == 16'd0) ? 16'd1 : (pair_min_i > 16'd255) ? 16'd255 : pair_min_i;
      pair_max <= (pair_max_i == 16'd0) ? 16'd1 : (pair_max_i > 16'd255) ? 16'd255 : pair_max_i;
      patience <= patience_i;
      lambda <= lambda_i;
    end
  end

  always @(posedge clk) begin
    if (!rst_n)
      x <= 0;
    else if ((state == S_IDLE) & start_i)
      x <= initial_x;
    else if (state == S_STEP)
      x <= next_x[31:0];
  end

  always @(posedge clk) begin
    if (!rst_n) begin
      power_a <= 0;
      power_b <= 0;
    end else begin
      if ((state == S_MEASURE_A) & amp_valid_i)
        power_a <= amp_data_i;

      if ((state == S_MEASURE_B) & amp_valid_i)
        power_b <= amp_data_i;
    end
  end

  always @(posedge clk) begin
    if (!rst_n) begin
      freq_word_o <= 0;
      freq_valid_o <= 0;
      probe_arm_o <= 0;
    end else if (state == S_PRESENT_A) begin
      freq_word_o <= probe_first;
      freq_valid_o <= ~freq_ack_i;
      probe_arm_o <= freq_ack_i;
    end else if (state == S_PRESENT_B) begin
      freq_word_o <= probe_second;
      freq_valid_o <= ~freq_ack_i;
      probe_arm_o <= freq_ack_i;
    end else begin
      probe_arm_o <= 0;

      if (state == S_IDLE)
        freq_valid_o <= 0;
    end
  end

  always @(posedge clk) begin
    if (!rst_n)
      done_o <= 0;
    else
      done_o <= (state == S_DONE);
  end

  always @(posedge clk) begin
    if (!rst_n)
      busy_o <= 0;
    else if ((state == S_IDLE) & start_i)
      busy_o <= 1;
    else if (state == S_DONE)
      busy_o <= 0;
  end

  always @(posedge clk) begin
    if (!rst_n) begin
      converged_o <= 0;
      capped_o <= 0;
    end else if ((state == S_IDLE) & start_i) begin
      converged_o <= 0;
      capped_o <= 0;
    end else if (state == S_CONVERGE) begin
      if (patience_converged)
        converged_o <= 1;
      else if (iteration >= max_iteration)
        capped_o <= 1;
    end
  end

endmodule
