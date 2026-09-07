#---------------------------
# QICK_PROCESSOR False Paths
#---------------------------

# General Synchronizers
set_false_path -to [get_pins -filter {REF_PIN_NAME =~ D} -of_objects [get_cells -hier -filter {name=~*_cdc_reg*}]]

# Specific Paths
set_false_path -from [get_pins -filter {REF_PIN_NAME =~ C} -of_objects [get_cells -hier -filter {name =~ *QPROC/QPROC_CTRL/c_time_ref_o_reg*}]] -to [get_pins -filter {REF_PIN_NAME =~ D} -of_objects [get_cells -hier -filter {name =~ *QPROC/QPROC_xREG/QPROC_xREG/axi_rdata_reg*}]]
set_false_path -from [get_pins -filter {REF_PIN_NAME =~ C} -of_objects [get_cells -hier -filter {name =~ *QPROC/QPROC_CTRL/offset_dt_r_reg*}]]  -to [get_pins -filter {REF_PIN_NAME =~ D} -of_objects [get_cells -hier -filter {name =~ *QPROC/QPROC_CTRL/time_updt_dt_reg*}]]
set_false_path -from [get_pins -filter {REF_PIN_NAME =~ C} -of_objects [get_cells -hier -filter {name =~ *QPROC/QPROC_CTRL/tproc_cfg_sync_reg[9]}]]  -to [get_clocks -of_objects [get_ports -filter {name =~ t_clk_i}]]
set_false_path -from [get_pins -filter {REF_PIN_NAME =~ C} -of_objects [get_cells -hier -filter {name =~ *QPROC/QPROC_CTRL/QPER_TIME_READ.c_time_abs_r_reg*}]] -to [get_pins -filter {REF_PIN_NAME =~ D} -of_objects [get_cells -hier -filter {name =~ *QPROC/QPROC_xREG/QPROC_xREG/axi_rdata_reg*}]]

set_false_path -from [get_pins -filter {REF_PIN_NAME =~ C} -of_objects [get_cells -hier -filter {name =~ *QPROC/QPROC_xREG/QPROC_xREG/slv_*_reg*}]] -to [get_clocks -of_objects [get_ports -filter {name =~ c_clk_i}]]

set_false_path -from [get_pins -filter {REF_PIN_NAME =~ C} -of_objects [get_cells -hier -filter {name =~ *QPROC/IN_PORT_REG/*.port_dt_r_reg*}]] -to [get_pins -filter {REF_PIN_NAME =~ D} -of_objects [get_cells -hier -filter {name =~ *QPROC/xreg_TPROC_R_DT_reg*}]]

set_false_path -from [get_pins -filter {REF_PIN_NAME =~ C} -of_objects [get_cells -hier -filter {name =~ *QPROC/CORE_0/CORE_CPU/reg_bank/sreg_dt_reg*}]] -to [get_pins -filter {REF_PIN_NAME =~ D} -of_objects [get_cells -hier -filter {name =~ *QPROC/xreg_TPROC_R_DT_reg*}]]

set_false_path -from [get_pins -filter {REF_PIN_NAME =~ C} -of_objects [get_cells -hier -filter {name =~ *QPROC/CORE_*/CORE_CPU/reg_bank/LFSR_YES.lfsr/reg_lfsr_reg*}]] -to [get_pins -filter {REF_PIN_NAME =~ D} -of_objects [get_cells -hier -filter {name =~ *QPROC/xreg_TPROC_R_DT_reg*}]]

set_false_path -from [get_pins -filter {REF_PIN_NAME =~ C} -of_objects [get_cells -hier -filter {name =~ *QPROC/qp?_dt_r_reg*}]] -to [get_clocks -of_objects [get_ports -filter {name =~ ps_clk_i}]]

# Doesn't exist if parameter QNET = 0
set_false_path -quiet -from [get_pins -filter {REF_PIN_NAME =~ C} -of_objects [get_cells -hier -filter {name =~ *QPROC/qnet_dt_r_reg*}]] -to [get_clocks -of_objects [get_ports -filter {name =~ ps_clk_i}]]

# Doesn't exist if parameter QCOM = 0
set_false_path -quiet -from [get_pins -filter {REF_PIN_NAME =~ C} -of_objects [get_cells -hier -filter {name =~ *QPROC/qcom_dt_r_reg*}]] -to [get_clocks -of_objects [get_ports -filter {name =~ ps_clk_i}]]

# Doesn't exist if parameter DIVIDER = 0
set_false_path -quiet -from [get_pins -filter {REF_PIN_NAME =~ C} -of_objects [get_cells -hier -filter {name =~ *QPROC/QPER_DIV.div_*_r_reg*}]] -to [get_pins -filter {REF_PIN_NAME =~ D} -of_objects [get_cells -hier -filter {name =~ *QPROC/xreg_TPROC_R_DT_reg*}]]

# Doesn't exist if parameter ARITH = 0
set_false_path -quiet -from [get_pins -filter {REF_PIN_NAME =~ CLK} -of_objects [get_cells -hier -filter {name =~ *QPROC/QPER_ARITH.ARITH/ARITH_DSP*i_primitive*}]] -to [get_pins -filter {REF_PIN_NAME =~ D} -of_objects [get_cells -hier -filter {name =~ *QPROC/xreg_TPROC_R_DT_reg*}]]

# Doesn't exist if parameter TIME_READ = 0
set_false_path -quiet -from [get_pins -filter {REF_PIN_NAME =~ C} -of_objects [get_cells -hier -filter {name =~ *QPROC/QPROC_CTRL/*t_time_abs_r_reg*}]]  -to [get_pins -filter {REF_PIN_NAME =~ D} -of_objects [get_cells -hier -filter {name =~ *QPROC/QPROC_CTRL/*c_time_abs_r_reg*}]]

# Doesn't exist if parameter DEBUG = 0
set_false_path -quiet -from [get_clocks -of_objects [get_ports -filter {name =~ t_clk_i}]] -to [get_pins -filter {REF_PIN_NAME =~ D} -of_objects [get_cells -hier -filter {name =~ *QPROC/AXI_DB.xreg_TPROC_DEBUG_reg*}]]
set_false_path -quiet -from [get_clocks -of_objects [get_ports -filter {name =~ t_clk_i}]] -to [get_pins -filter {REF_PIN_NAME =~ D} -of_objects [get_cells -hier -filter {name =~ *QPROC/AXI_DB.xreg_TPROC_STATUS_reg*}]]
set_false_path -quiet -from [get_clocks -of_objects [get_ports -filter {name =~ c_clk_i}]] -to [get_pins -filter {REF_PIN_NAME =~ D} -of_objects [get_cells -hier -filter {name =~ *QPROC/AXI_DB.xreg_TPROC_DEBUG_reg*}]]
set_false_path -quiet -from [get_clocks -of_objects [get_ports -filter {name =~ c_clk_i}]] -to [get_pins -filter {REF_PIN_NAME =~ D} -of_objects [get_cells -hier -filter {name =~ *QPROC/AXI_DB.xreg_TPROC_STATUS_reg*}]]

set qick_cdc_sync_cells [get_cells -quiet -hier -filter {NAME =~ *QPROC/IPC_CDC/c_request_sync_reg* || NAME =~ *QPROC/IPC_CDC/ps_ack_sync_reg* || NAME =~ *QPROC/DISPATCHER/t_trig_flush_sync_reg* || NAME =~ *QPROC/DISPATCHER/c_trig_ack_sync_reg* || NAME =~ *QPROC/DISPATCHER/t_trig_reset_done_sync_reg*}]
foreach qick_cdc_sync_cell $qick_cdc_sync_cells {
    if {[regexp {_reg\[0\]($|_)} $qick_cdc_sync_cell]} {
        set_false_path -to [get_pins -of_objects $qick_cdc_sync_cell -filter {REF_PIN_NAME == D}]
    }
}

foreach qick_cdc_bundle {
    {IPC_CDC ps_payload_reg c_ipc_reg ps_request_reg c_request_sync_reg 1.0}
    {DISPATCHER c_trig_flush_mask_reg t_trig_mask_cdc_reg c_trig_flush_toggle_reg t_trig_flush_sync_reg 0.5}
} {
    lassign $qick_cdc_bundle qick_cdc_inst qick_cdc_payload_name qick_cdc_data_name qick_cdc_request_name qick_cdc_sync_name qick_cdc_fraction
    set qick_cdc_payload [get_cells -quiet -hier -filter "NAME =~ *QPROC/$qick_cdc_inst/$qick_cdc_payload_name*"]
    set qick_cdc_data [get_cells -quiet -hier -filter "NAME =~ *QPROC/$qick_cdc_inst/$qick_cdc_data_name*"]
    if {[llength $qick_cdc_payload] && [llength $qick_cdc_data]} {
        set qick_cdc_request [get_cells -quiet -hier -filter "NAME =~ *QPROC/$qick_cdc_inst/$qick_cdc_request_name*"]
        set qick_cdc_request_capture {}
        foreach qick_cdc_sync_cell [get_cells -quiet -hier -filter "NAME =~ *QPROC/$qick_cdc_inst/$qick_cdc_sync_name*"] {
            if {[regexp {_reg\[0\]($|_)} $qick_cdc_sync_cell]} {
                lappend qick_cdc_request_capture $qick_cdc_sync_cell
            }
        }
        if {![llength $qick_cdc_request] || ![llength $qick_cdc_request_capture]} {
            error "QICK $qick_cdc_inst CDC request registers were not found for the data bundle"
        }
        set qick_cdc_source_clock [get_clocks -of_objects [get_pins -of_objects $qick_cdc_payload -filter {REF_PIN_NAME == C}]]
        set qick_cdc_capture_clock [get_clocks -of_objects [get_pins -of_objects $qick_cdc_data -filter {REF_PIN_NAME == C}]]
        if {![llength $qick_cdc_source_clock] || ![llength $qick_cdc_capture_clock]} {
            error "QICK $qick_cdc_inst CDC bundle clocks were not found"
        }
        set qick_cdc_limit [expr {$qick_cdc_fraction * min([get_property -min PERIOD $qick_cdc_source_clock], [get_property -min PERIOD $qick_cdc_capture_clock])}]
        set_false_path -from $qick_cdc_payload -to $qick_cdc_data
        set_bus_skew $qick_cdc_limit -from [concat $qick_cdc_payload $qick_cdc_request] -to [concat $qick_cdc_data $qick_cdc_request_capture]
    }
}
