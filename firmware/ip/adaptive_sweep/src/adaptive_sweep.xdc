#---------------------------
# adaptive_sweep False Paths
#---------------------------

# Debug views: clk -> s_axi_aclk capture (dbg_*_axi) and the REG2 read select the other way.
set_false_path -to [get_pins -filter {REF_PIN_NAME =~ D} -of_objects [get_cells -hier -filter {name =~ *registers/dbg_*_axi_reg*}]]
set_false_path -to [get_pins -filter {REF_PIN_NAME =~ D} -of_objects [get_cells -hier -filter {name =~ *registers/read_sel_s0_reg*}]]

# AXI writes: the REG0[31] toggle enters clk through toggle_s0/s1; the target and the payload are
# written a transaction before the toggle and are only sampled on the synchronized pulse.
set_false_path -to [get_pins -filter {REF_PIN_NAME =~ D} -of_objects [get_cells -hier -filter {name =~ *registers/toggle_s0_reg*}]]
set_false_path -from [get_cells -hier -filter {name =~ *registers/axi_slave/payload_reg* || name =~ *registers/axi_slave/target_reg*}] -to [get_cells -hier -filter {name =~ *registers/threshold_o_reg* || name =~ *registers/block_tol_o_reg* || name =~ *monitor/axi_target_reg* || name =~ *monitor/axi_bad_target_reg*}]
