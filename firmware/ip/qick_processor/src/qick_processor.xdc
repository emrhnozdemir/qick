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

set_false_path -to [get_pins -of_objects [get_cells -hier -regexp {^.*QPROC/IPC_CDC/c_request_sync_reg\[0\]$}] -filter {REF_PIN_NAME == D}]
set_false_path -to [get_pins -of_objects [get_cells -hier -regexp {^.*QPROC/IPC_CDC/ps_ack_sync_reg\[0\]$}] -filter {REF_PIN_NAME == D}]
set_false_path -to [get_pins -of_objects [get_cells -hier -regexp {^.*QPROC/DISPATCHER/t_trig_flush_sync_reg\[0\]$}] -filter {REF_PIN_NAME == D}]
set_false_path -to [get_pins -of_objects [get_cells -hier -regexp {^.*QPROC/DISPATCHER/c_trig_ack_sync_reg\[0\]$}] -filter {REF_PIN_NAME == D}]
set_false_path -to [get_pins -of_objects [get_cells -hier -regexp {^.*QPROC/DISPATCHER/t_trig_reset_done_sync_reg\[0\]$}] -filter {REF_PIN_NAME == D}]

set qick_ipc_payload [get_cells -hier -regexp {^.*QPROC/IPC_CDC/ps_payload_reg\[[0-9]+\]$}]
set qick_ipc_data [get_cells -hier -regexp {^.*QPROC/IPC_CDC/c_ipc_reg\[[0-9]+\]$}]
set qick_ipc_source_clock [get_clocks -of_objects [get_pins -of_objects $qick_ipc_payload -filter {REF_PIN_NAME == C}]]
set qick_ipc_capture_clock [get_clocks -of_objects [get_pins -of_objects $qick_ipc_data -filter {REF_PIN_NAME == C}]]
set qick_ipc_limit [expr {min([get_property -min PERIOD $qick_ipc_source_clock], [get_property -min PERIOD $qick_ipc_capture_clock])}]
set_false_path -from $qick_ipc_payload -to $qick_ipc_data
set_bus_skew $qick_ipc_limit -from [get_cells -hier -regexp {^.*QPROC/IPC_CDC/(ps_payload_reg\[[0-9]+\]|ps_request_reg)$}] -to [get_cells -hier -regexp {^.*QPROC/IPC_CDC/(c_ipc_reg\[[0-9]+\]|c_request_sync_reg\[0\])$}]

set qick_flush_payload [get_cells -hier -regexp {^.*QPROC/DISPATCHER/c_trig_flush_mask_reg\[[0-9]+\]$}]
set qick_flush_data [get_cells -hier -regexp {^.*QPROC/DISPATCHER/t_trig_mask_cdc_reg\[[0-9]+\]$}]
set qick_flush_source_clock [get_clocks -of_objects [get_pins -of_objects $qick_flush_payload -filter {REF_PIN_NAME == C}]]
set qick_flush_capture_clock [get_clocks -of_objects [get_pins -of_objects $qick_flush_data -filter {REF_PIN_NAME == C}]]
set qick_flush_limit [expr {0.5 * min([get_property -min PERIOD $qick_flush_source_clock], [get_property -min PERIOD $qick_flush_capture_clock])}]
set_false_path -from $qick_flush_payload -to $qick_flush_data
set_bus_skew $qick_flush_limit -from [get_cells -hier -regexp {^.*QPROC/DISPATCHER/(c_trig_flush_mask_reg\[[0-9]+\]|c_trig_flush_toggle_reg)$}] -to [get_cells -hier -regexp {^.*QPROC/DISPATCHER/(t_trig_mask_cdc_reg\[[0-9]+\]|t_trig_flush_sync_reg\[0\])$}]
