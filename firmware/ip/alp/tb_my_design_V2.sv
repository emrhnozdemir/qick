`timescale 1ns / 1ps

module tb_my_design_wrapper_v2();

    // ==========================================
    // Clock and Reset Generation
    // ==========================================
    reg clk;
    reg rst_n;

    always #5 clk = ~clk; // 100 MHz clock (10ns period)

    // ==========================================
    // Wrapper Interface Signals
    // ==========================================
    reg        qtag_en_i;
    reg  [4:0] qtag_op_i;
    reg  [31:0] qtag_dt1_i;
    reg  [31:0] qtag_dt2_i;
    reg  [31:0] qtag_dt3_i;
    reg  [31:0] qtag_dt4_i;
    
    wire        qtag_rdy_o;
    wire [31:0] qtag_dt1_o;
    wire [31:0] qtag_dt2_o;
    wire        qtag_vld_o;

    reg         trigger;
    wire [31:0] nsamp;
    reg         s_axis_tvalid;
    wire [31:0] s_axis_tdata;

    // Fixed ADC stream control
    assign nsamp = 32'd256; // 256 samples per trigger

    // ==========================================
    // Module Instantiation
    // ==========================================
    my_design_wrapper #(
        .MAX_AVG(64)
    ) uut (
        .clk(clk),
        .rst_n(rst_n),
        .qtag_en_i(qtag_en_i),
        .qtag_op_i(qtag_op_i),
        .qtag_dt1_i(qtag_dt1_i),
        .qtag_dt2_i(qtag_dt2_i),
        .qtag_dt3_i(qtag_dt3_i),
        .qtag_dt4_i(qtag_dt4_i),
        .qtag_rdy_o(qtag_rdy_o),
        .qtag_dt1_o(qtag_dt1_o),
        .qtag_dt2_o(qtag_dt2_o),
        .qtag_vld_o(qtag_vld_o),
        .trigger(trigger),
        .nsamp(nsamp),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tdata(s_axis_tdata)
    );

    // ==========================================
    // Simulated ADC Peak Generation Environment
    // ==========================================
    parameter PEAK_FREQ  = 32'd18000000; // Peak in the middle of start and stop
    parameter PEAK_WIDTH = 32'd2000000;  // +/- width for the peak slope
    
    reg [31:0] read_freq_word;
    reg [15:0] current_adc_amp;
    reg        toggle_sign;

    // Calculate synthetic ADC amplitude based on proximity to PEAK_FREQ
    always @(*) begin
        integer diff;
        diff = read_freq_word - PEAK_FREQ;
        if (diff < 0) diff = -diff; // Absolute difference

        if (diff < PEAK_WIDTH) begin
            // Linear slope up to max amplitude of ~30000
            current_adc_amp = 16'd30000 - ((diff * 16'd29000) / PEAK_WIDTH); 
        end else begin
            // Noise floor
            current_adc_amp = 16'd1000; 
        end
    end

    // Generate oscillating ADC data (simulating a complex AC waveform)
    always @(posedge clk) begin
        if (!rst_n) begin
            toggle_sign <= 1'b0;
        end else begin
            toggle_sign <= ~toggle_sign; // Create a simple square wave toggle
        end
    end

    // Create 16-bit I and Q pairs
    wire signed [15:0] i_samp = toggle_sign ? current_adc_amp : -current_adc_amp;
    wire signed [15:0] q_samp = toggle_sign ? -current_adc_amp : current_adc_amp;
    
    assign s_axis_tdata = {i_samp, q_samp}; 

    // ==========================================
    // Main Test Sequence (Software Simulator)
    // ==========================================
    reg sw_finish;
    
    initial begin
        // 1. Initialize Default Values
        clk = 0;
        rst_n = 0;
        qtag_en_i = 0;
        qtag_op_i = 0;
        qtag_dt1_i = 0;
        qtag_dt2_i = 0;
        qtag_dt3_i = 0;
        qtag_dt4_i = 0;
        trigger = 0;
        s_axis_tvalid = 0;
        read_freq_word = 0;
        sw_finish = 0;

        // Release Reset
        #100;
        rst_n = 1;
        #100;
        $display("-------------------------------------------------");
        $display("[%0t] SYSTEM RESET COMPLETE", $time);

        // 2. Opcode 0: Coarse Search Configuration
        @(posedge clk); #1; 
        qtag_en_i  = 1'b1;
        qtag_op_i  = 5'd0;
        qtag_dt1_i = 32'd6000000;   // Start Freq
        qtag_dt2_i = 32'd30000000;  // Stop Freq
        qtag_dt3_i = 32'd10000000;  // First Sweep Step (10 MHz)
        qtag_dt4_i = 32'd3;         // Averager Value
        
        @(posedge clk); #1;
        qtag_en_i  = 1'b0;
        $display("[%0t] OPCODE 0 SENT: Start=%0d, Stop=%0d, Coarse Step=%0d", $time, qtag_dt1_i, qtag_dt2_i, qtag_dt3_i);
        #50;

        // 3. Opcode 1: Fine Tune Configuration & Start
        @(posedge clk); #1;
        qtag_en_i  = 1'b1;
        qtag_op_i  = 5'd1;
        qtag_dt1_i = 32'd1000000;   // Second Sweep Step (1 MHz)
        qtag_dt2_i = 32'd5000000;   // Second Sweep Window (+/- 5 MHz)
        
        @(posedge clk); #1;
        qtag_en_i  = 1'b0;
        $display("[%0t] OPCODE 1 SENT: Fine Step=%0d, Fine Window=%0d", $time, qtag_dt1_i, qtag_dt2_i);
        $display("[%0t] SWEEP STARTED! Target Resonant Peak is at %0d", $time, PEAK_FREQ);
        $display("-------------------------------------------------");

        // 4. Autonomous Loopback Routine
        while (!sw_finish) begin
            
            // Wait for the Wrapper to push data out autonomously
            @(posedge clk);
            if (qtag_vld_o) begin
                // Read the pushed data
                read_freq_word = qtag_dt1_o;
                sw_finish      = qtag_dt2_o[0]; // Sticky Finish bit
                
                if (sw_finish) begin
                    $display("-------------------------------------------------");
                    $display("[%0t] SWEEP FINISHED DETECTED!", $time);
                    $display("[%0t] Final best frequency reported: %0d", $time, read_freq_word);
                    $display("-------------------------------------------------");
                end 
                else if (qtag_dt2_o[1]) begin // freq_valid bit
                    $display("[%0t] Hardware Pushed Freq: %0d | Synthesizing I/Q Peak Amp: %0d", $time, read_freq_word, current_adc_amp);
                    
                    // Simulate DAC Write & settling delay
                    repeat(40) @(posedge clk); 
                    
                    // Trigger the capture and turn on the ADC data stream
                    @(posedge clk); #1;
                    trigger = 1'b1;
                    s_axis_tvalid = 1'b1; // Turn on Data Valid
                    
                    @(posedge clk); #1;
                    trigger = 1'b0;

                    // Keep Valid high for the duration of nsamp + a small buffer
                    repeat(260) @(posedge clk);
                    #1; s_axis_tvalid = 1'b0; // Turn off Data Valid

                    // Wait enough time for the amplitude_calculator to finish its processing
                    repeat(100) @(posedge clk);
                end
            end
        end

        // End Simulation
        #500;
        $display("[%0t] SIMULATION COMPLETE.", $time);
        $finish;
    end

endmodule