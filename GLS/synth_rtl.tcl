set_db init_hdl_search_path {../RTL ../RTL/soc_uart_subsystem/uart_top}

set_db library "/home/install/SCL180/SCLPDK_V3.0_KIT/scl180/stdcell/fs120/4M1IL/liberty/lib_flow_ss/tsl18fs120_scl_ss.lib /home/install/SCL180/SCLPDK_V3.0_KIT/scl180/memory/spram/4M1L/SPRAM_2048x36/SPRAM_2048x36_max_SP.lib /home/install/SCL180/SCLPDK_V3.0_KIT/scl180/memory/spram/4M1L/SPRAM_1024x36/SPRAM_1024x36_max_SP.lib"

read_hdl -sv -f full_rtl.f

set_db optimize_constant_0_flops false

set_db optimize_constant_1_flops false

elaborate system

read_sdc constraints_full.sdc

syn_generic

write_hdl > netlist_gen.v

set_db [get_cells -hierarchical {*mem_addr*}] .optimize_constant_feedback_seq false
set_db [get_cells -hierarchical {*mem_state*}] .optimize_constant_feedback_seq false
set_db [get_cells -hierarchical {*lsr*}] .optimize_constant_feedback_seq false
set_db [get_cells -hierarchical {*pcpi_rd*}] .optimize_constant_feedback_seq false
set_db [get_cells -hierarchical {*mem_rdata*}] .optimize_constant_feedback_seq false
set_db [get_cells -hierarchical {*mem_wdata*}] .optimize_constant_feedback_seq false
set_db [get_cells -hierarchical {*mem_ready*}] .optimize_constant_feedback_seq false
set_db [get_cells -hierarchical {*SRAM_ADDR*}] .optimize_constant_feedback_seq false
set_db [get_cells -hierarchical {*SRAM_ADDR_0*}] .optimize_constant_feedback_seq false
set_db [get_cells -hierarchical {*SRAM_ADDR_1*}] .optimize_constant_feedback_seq false
set_db [get_cells -hierarchical {*SRAM_ADDR_2*}] .optimize_constant_feedback_seq false
set_db [get_cells -hierarchical {*SRAM_ADDR_3*}] .optimize_constant_feedback_seq false
set_db [get_cells -hierarchical {*SRAM_WDATA*}] .optimize_constant_feedback_seq false

syn_map

write_hdl > netlist_map.v

syn_opt

write_hdl > netlist_opt.v

report_gates

