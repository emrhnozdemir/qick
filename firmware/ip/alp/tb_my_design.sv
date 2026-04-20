`timescale 1ns / 1ps

module tb_my_design_wrapper();

    // ==========================================
    // Clock and Reset Generation
    // ==========================================
    reg clk;
    reg rst_n;

    always #5 clk = ~clk; // 100 MHz clock (10ns period)

    // ==========================================
    // Wrapper Interface Signals
    // ==========================================
    reg         qtag_en_i;
    reg  [4:0]  qtag_op_i;
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
    wire        s_axis_tvalid;
    wire [31:0] s_axis_tdata;

    // Fixed ADC stream control
    assign nsamp         = 32'd256; // 256 samples per trigger
    assign s_axis_tvalid = 1'b1;    // Always valid

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

    // Generate oscillating ADC data (simulating a complex AC waveform to the calculator)
    always @(posedge clk) begin
        if (!rst_n) begin
            toggle_sign <= 1'b0;
        end else begin
            toggle_sign <= ~toggle_sign; // Create a simple square wave toggle
        end
    end

    // Create 16-bit I and Q pairs. 
    // They are packed into the 32-bit s_axis_tdata port.
    wire signed [15:0] i_samp = toggle_sign ? current_adc_amp : -current_adc_amp;
    wire signed [15:0] q_samp = toggle_sign ? -current_adc_amp : current_adc_amp;
    
    assign s_axis_tdata = {i_samp, q_samp}; 

    // ==========================================
    // Main Test Sequence (Software Simulator)
    // ==========================================
    reg [31:0] read_flags;
    reg        sw_freq_valid;
    reg        sw_finish;
    
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
        read_freq_word = 0;

        // Release Reset
        #100;
        rst_n = 1;
        #100;
        $display("-------------------------------------------------");
        $display("[%0t] SYSTEM RESET COMPLETE", $time);

        // 2. Opcode 0: Configuration
        // ADDED #1 AFTER POSEDGE TO PREVENT RACE CONDITIONS
        @(posedge clk); #1; 
        qtag_en_i  = 1'b1;
        qtag_op_i  = 5'd0;
        qtag_dt1_i = 32'd6000000;   // Start Freq
        qtag_dt2_i = 32'd30000000;  // Stop Freq
        qtag_dt3_i = 32'd3;         // Averager Value
        
        @(posedge clk); #1;
        qtag_en_i  = 1'b0;
        $display("[%0t] CONFIG SENT: Start=6000000, Stop=30000000, Avg=3", $time);
        #50;

        // 3. Opcode 1: Start Sweeping
        @(posedge clk); #1;
        qtag_en_i = 1'b1;
        qtag_op_i = 5'd1;
        
        @(posedge clk); #1;
        qtag_en_i = 1'b0;
        $display("[%0t] SWEEP STARTED! Target Resonant Peak is at %0d", $time, PEAK_FREQ);
        $display("-------------------------------------------------");

        // 4. Polling Loop
        sw_finish = 1'b0;
        
        while (!sw_finish) begin
            // Wait simulated software polling delay
            repeat(15) @(posedge clk);

            // Read Opcode 2
            @(posedge clk); #1;
            qtag_en_i = 1'b1;
            qtag_op_i = 5'd2;
            
            @(posedge clk); #1;
            qtag_en_i = 1'b0;

            // Wait for Wrapper Acknowledge (Wait until valid is high)
            while (!qtag_vld_o) @(posedge clk);

            // Capture results slightly after the clock edge to be safe
            #1;
            read_freq_word = qtag_dt1_o;
            read_flags     = qtag_dt2_o;

            sw_freq_valid = read_flags[1];
            sw_finish     = read_flags[0];

            if (sw_finish) begin
                $display("-------------------------------------------------");
                $display("[%0t] SWEEP FINISHED DETECTED BY SOFTWARE!", $time);
                $display("[%0t] Final best frequency reported: %0d", $time, read_freq_word);
                $display("-------------------------------------------------");
            end 
            else if (sw_freq_valid) begin
                $display("[%0t] SW Read Freq: %0d | Synthesizing I/Q Peak Amp: %0d", $time, read_freq_word, current_adc_amp);
                
                // Simulate DAC Write Delay (Software writing to DAC over SPI/I2C)
                repeat(40) @(posedge clk); 
                
                // Trigger the amplitude calculator to capture ADC samples
                @(posedge clk); #1;
                trigger = 1'b1;
                
                @(posedge clk); #1;
                trigger = 1'b0;

                // Wait enough time for the amplitude_calculator to process
                repeat(300) @(posedge clk);
            end
        end

        // End Simulation
        #500;
        $display("[%0t] SIMULATION COMPLETE.", $time);
        $finish;
    end

endmodule