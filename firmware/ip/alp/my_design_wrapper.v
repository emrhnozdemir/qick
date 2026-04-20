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

    input  wire        start,
    input  wire [31:0] start_freq,
    input  wire [31:0] stop_freq,
    
    input  wire        trigger,
    input  wire [31:0] nsamp,
    input  wire [$clog2(MAX_AVG)-1:0] averager_value,

    input  wire        s_axis_tvalid,
    input  wire [31:0] s_axis_tdata,

    output wire [31:0] freq_word,
    output wire        freq_valid,
    output wire        finish
);
    
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

        .start           (start),             
        .start_freq      (start_freq),        
        .stop_freq       (stop_freq),         

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
        .averager_value (averager_value),     

        .m_axis_tdata   (w_amplitude_data),   
        .m_axis_tvalid  (w_amplitude_valid),  
        .one_burst_done (w_one_burst_done)    
    );
endmodule
