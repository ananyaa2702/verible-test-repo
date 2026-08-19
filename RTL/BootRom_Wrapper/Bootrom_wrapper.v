`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Shashank Tiwari, Samyak Nidhi, Tanish A Shet, Rakesh Patil
// Last Modified: 03.04.2026
// Module Name: Bootrom_wrapper
// Project Name: Silicon SoC KNN
// Description:
// Wrapper for bootrom access and CSR control logic.
// Instantiates bootrom and SRAM_CSR_logic modules and connects them together.
// DUAL FLOW IMPLEMENTATION:
// - FOR_FPGA (synthesis): Uses blk_mem_gen_0 (Xilinx generated BRAM core) for efficient
//   FPGA resource usage. bootrom.v is preprocessor-excluded
// - Non-FPGA (simulation): Uses bootrom_behav behavioral model (bootrom.v) for RTL simulation
//   without FPGA-specific IP dependencies. bootrom.v appears in simulation hierarchy only.
//////////////////////////////////////////////////////////////////////////////////

// Uncomment for ASIC Cadence
// `include "global_defines.v"

module Bootrom_wrapper
(
	input  wire        clk,
	input  wire        resetn,
	input  wire [31:0] mem_addr,
	input  wire [31:0] mem_wdata,
	input  wire        bootrom_wea, // Active when writing to bootrom (should be 0 in practice)
	input  wire        bootrom_valid, // Active when accessing bootrom address range
	input  wire        SRAM_CSR_Valid, // Active when accessing SRAM CSR address
	input  wire [3:0]  mem_wstrb, // Active when writing to SRAM CSR
	input  wire        boot_en, // Active when boot_controller is loading firmware to SRAM (flash -> core)

	output wire [31:0] CSR_rdata, // Data read from bootrom or CSR
	output wire        SRAM_CSR_ready, // Indicates data is ready (For CSR Only)
	// Bootrom outputs
	output wire [31:0] bootrom_rdata,
	// CSR status output
	output wire        load_done_core,
	output wire        load_busy_core
);

//----------------------------------//
// Bootrom instantiation
//----------------------------------//
`ifdef BEHAV_BOOTROM
bootrom bootrom_behav (
	.clk(clk),
	.rst_n(resetn),
	.addr({2'b00, mem_addr[31:2]}), // word address
	.ce(bootrom_valid), // Enable when accessing bootrom
	.dataout(bootrom_rdata)
);
`else
	`ifdef FOR_FPGA
	blk_mem_gen_0 bootrom (
		.clka(clk),
		.rsta(~resetn),
		.ena(bootrom_valid), // Enable when accessing bootrom
		.wea(bootrom_wea), // Allow writes to bootrom for testing, but should be 0 in practice
		.addra(mem_addr[31:2]), // word address
		.dina(mem_wdata), // Data input for writes (not used in practice)
		.douta(bootrom_rdata)
	);
	`endif

`endif

//----------------------------------//
// SRAM CSR logic instantiation
//----------------------------------//
SRAM_CSR_logic u_SRAM_CSR_logic (
	.clk(clk),
	.resetn(resetn),
	.mem_wdata(mem_wdata),
	.mem_wstrb(mem_wstrb),
	.SRAM_CSR_Valid(SRAM_CSR_Valid),
	.boot_en(boot_en),

	.CSR_rdata(CSR_rdata),
	.SRAM_CSR_ready(SRAM_CSR_ready),
	.load_done_core(load_done_core),
	.load_busy_core(load_busy_core)
);

endmodule
