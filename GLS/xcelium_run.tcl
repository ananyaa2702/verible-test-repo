# Just for functional sim - UART
xrun -notimingchecks -xminitialize rand:0 -access +rwc +maxdelays -delay_mode unit -timescale 1ns/1ps /home/install/SCL180/SCLPDK_V3.0_KIT/scl180/stdcell/fs120/4M1IL/verilog/vcs_sim_model/tsl18fs120_scl.v /home/install/SCL180/SCLPDK_V3.0_KIT/scl180/memory/spram/4M1L/SPRAM_2048x36/SPRAM_2048x36.v /home/install/SCL180/SCLPDK_V3.0_KIT/scl180/memory/spram/4M1L/SPRAM_1024x36/SPRAM_1024x36.v \ netlist_opt.v \ ../TB/uart_rx_sim.v \ ../TB/tb_uart_with_firmware.sv \ ../TB/W25Q16JV.v \  -incdir ../RTL -incdir ../memh_files -gui

# Just for functional sim - FLASH
xrun -notimingchecks -xminitialize rand:0 -access +rwc +maxdelays -delay_mode unit -timescale 1ns/1ps /home/install/SCL180/SCLPDK_V3.0_KIT/scl180/stdcell/fs120/4M1IL/verilog/vcs_sim_model/tsl18fs120_scl.v /home/install/SCL180/SCLPDK_V3.0_KIT/scl180/memory/spram/4M1L/SPRAM_2048x36/SPRAM_2048x36.v /home/install/SCL180/SCLPDK_V3.0_KIT/scl180/memory/spram/4M1L/SPRAM_1024x36/SPRAM_1024x36.v \ netlist_opt.v \ ../TB/uart_rx_sim.v \ ../TB/tb_flash_with_firmware.sv \ ../TB/s25fl128s.v \  -incdir ../RTL -incdir ../flash_memory_files -gui

# For flash path
xrun -access +rwc -timescale 1ns/1ps /home/install/SCL180/SCLPDK_V3.0_KIT/scl180/stdcell/fs120/4M1IL/verilog/vcs_sim_model/tsl18fs120_scl.v /home/install/SCL180/SCLPDK_V3.0_KIT/scl180/memory/spram/4M1L/SPRAM_2048x36/SPRAM_2048x36.v /home/install/SCL180/SCLPDK_V3.0_KIT/scl180/memory/spram/4M1L/SPRAM_1024x36/SPRAM_1024x36.v \ netlist_opt.v \ ../TB/uart_rx_sim.v \ ../TB/tb_flash_with_firmware.sv \ ../TB/s25fl128s.v \  -incdir ../RTL -sdf_verbose -sdfstats sdf_stats_flash.txt -mess -relax -gui

# For UART path
xrun -access +rwc -timescale 1ns/1ps /home/install/SCL180/SCLPDK_V3.0_KIT/scl180/stdcell/fs120/4M1IL/verilog/vcs_sim_model/tsl18fs120_scl.v /home/install/SCL180/SCLPDK_V3.0_KIT/scl180/memory/spram/4M1L/SPRAM_2048x36/SPRAM_2048x36.v /home/install/SCL180/SCLPDK_V3.0_KIT/scl180/memory/spram/4M1L/SPRAM_1024x36/SPRAM_1024x36.v \ netlist_opt.v \ ../TB/uart_rx_sim.v \ ../TB/tb_uart_with_firmware.sv \ ../TB/W25Q16JV.v \  -incdir ../RTL -sdf_verbose -sdfstats sdf_stats_flash.txt -mess -relax -gui
