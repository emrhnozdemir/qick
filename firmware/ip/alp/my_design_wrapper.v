`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 20.04.2026 15:44:03
// Design Name: 
// Module Name: my_design_wrapper
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module my_design_wrapper #(
    parameter MAX_AVG = 64
)(
    input  wire        clk,
    input  wire        rst_n,

    input  wire        qtag_en_i,
    input  wire [4:0]  qtag_op_i,
    input  wire [31:0] qtag_dt1_i,
    input  wire [31:0] qtag_dt2_i,
    input  wire [31:0] qtag_dt3_i,
    input  wire [31:0] qtag_dt4_i,
    output reg         qtag_rdy_o,
    output reg  [31:0] qtag_dt1_o,
    output reg  [31:0] qtag_dt2_o,
    output reg         qtag_vld_o,

    input  wire        trigger,
    input  wire [31:0] nsamp,
    input  wire        s_axis_tvalid,
    input  wire [31:0] s_axis_tdata

//    output wire [31:0] freq_word,
//    output wire        freq_valid,
//    output wire        finish
);
    reg sticky_finish;
    reg sticky_freq_valid;
    //
    wire [31:0] freq_word;
    wire        freq_valid;
    wire        finish;
    
    reg en_d;
    wire en_rise;

    reg [31:0] reg_start_freq;
    reg [31:0] reg_stop_freq;
    reg [$clog2(MAX_AVG)-1:0] reg_averager_value;
    
    wire w_start_pulse;

    assign en_rise = qtag_en_i & ~en_d;
    
    wire w_read_pulse  = en_rise & (qtag_op_i == 5'd2);
    
    assign w_start_pulse = en_rise & (qtag_op_i == 5'd1);
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sticky_finish     <= 1'b0;
            sticky_freq_valid <= 1'b0;
        end else begin
            // Clear everything on a fresh start
            if (w_start_pulse) begin
                sticky_finish     <= 1'b0;
                sticky_freq_valid <= 1'b0;
            end else begin
                // FINISH logic (only happens once at the very end, no need to clear)
                if (finish) sticky_finish <= 1'b1;

                // FREQ_VALID logic
                if (freq_valid) begin
                    sticky_freq_valid <= 1'b1; // Set to 1 when a new frequency is ready
                end else if (w_read_pulse) begin
                    sticky_freq_valid <= 1'b0; // CLEAR to 0 the moment the software reads it!
                end
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            en_d <= 1'b0;
        else
            en_d <= qtag_en_i;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            qtag_rdy_o         <= 1'b1;
            qtag_vld_o         <= 1'b0;
            qtag_dt1_o         <= 32'd0;
            qtag_dt2_o         <= 32'd0;
            reg_start_freq     <= 32'd0;
            reg_stop_freq      <= 32'd0;
            reg_averager_value <= 0;
        end else begin
            qtag_vld_o <= 1'b0; // Default to 0 unless reading back data

            if (en_rise) begin
                case (qtag_op_i)
                    5'd0: begin
                        
                        reg_start_freq     <= qtag_dt1_i;
                        reg_stop_freq      <= qtag_dt2_i;
                        reg_averager_value <= qtag_dt3_i[$clog2(MAX_AVG)-1:0];
                    end
                    5'd1: begin
                        // OPCODE 1: Start Processing
                        // Handled by the w_start_pulse wire above. 
                        // No register updates needed here.
                    end
                    5'd2: begin
                        // OPCODE 2: Read Results
                        qtag_dt1_o <= freq_word;
            
                        // Send the STICKY bits
                        qtag_dt2_o <= {30'd0, sticky_freq_valid, sticky_finish}; 
            
                        qtag_vld_o <= 1'b1;             
                    end
                    default: begin
                    end
                endcase
            end
        end
    end
    
    wire [63:0] w_amplitude_data;  // Adjust width if you change ACCUM_WIDTH
    wire        w_amplitude_valid;
    wire        w_one_burst_done;
      
    peak_finder #(
        .first_sweep   (10000000),      // 10 MHz step
        .second_sweep  (1000000),       // 1 MHz step
        .second_window (5000000),       // +-5MHz fine tuning
        .ADC_DAC_freq  (64'd491520000), // 491.52 MHz
        .MAX_AVG       (64),
        .ACCUM_WIDTH   (64)
    ) u_peak_finder (
        .clk             (clk),               
        .rstn            (rst_n),             

        .start           (w_start_pulse),             
        .start_freq      (reg_start_freq),        
        .stop_freq       (reg_stop_freq),         

        .amplitude_valid (w_amplitude_valid), 
        .amplitude_data  (w_amplitude_data),  
        .one_sample_done (w_one_burst_done),  

        .freq_word       (freq_word),         
        .freq_valid      (freq_valid),        
        .finish          (finish)             
    );

    amplitude_calculator_v3 #(
        .MAX_AVG       (64),
        .ACCUM_WIDTH   (64)
    ) u_amplitude_calculator (
        .clk            (clk),                
        .rst_n          (rst_n),              

        .s_axis_tvalid  (s_axis_tvalid),      
        .s_axis_tdata   (s_axis_tdata),       

        .trigger        (trigger),            
        .nsamp          (nsamp),              
        .averager_value (reg_averager_value),     

        .m_axis_tdata   (w_amplitude_data),   
        .m_axis_tvalid  (w_amplitude_valid),  
        .one_burst_done (w_one_burst_done)    
    );
endmodule
