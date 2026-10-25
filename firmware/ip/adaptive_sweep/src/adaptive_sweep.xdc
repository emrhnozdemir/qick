#---------------------------
# adaptive_sweep False Paths
#---------------------------

# The debug views are produced in the clk domain and captured into s_axi_aclk
# by register_bank (dbg_*_axi); REG2's read select crosses the other way
# through read_sel_s0/s1. Debug data only, so neither path needs timing.
set_false_path -to [get_pins -filter {REF_PIN_NAME =~ D} -of_objects [get_cells -hier -filter {name =~ *registers/dbg_*_axi_reg*}]]
set_false_path -to [get_pins -filter {REF_PIN_NAME =~ D} -of_objects [get_cells -hier -filter {name =~ *registers/read_sel_s0_reg*}]]
