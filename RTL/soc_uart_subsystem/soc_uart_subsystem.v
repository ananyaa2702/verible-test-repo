`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Shashank Tiwari, Samyak Nidhi, Tanish A Shet, Rakesh Patil
// Last Modified: 03.04.2026
// Module Name: soc_uart_top
// Project Name: Silicon SoC KNN
// Description:
// Top-level UART integration module that bridges a native memory interface
// to the UART Wishbone interface and synchronizes the external serial input.
//////////////////////////////////////////////////////////////////////////////////

module soc_uart_subsystem
(
	// System inputs
	input  wire        clk,
	input  wire        sync_core_resetn,

	// RISC-V native memory interface
	input  wire        mem_valid,
	//input  wire        mem_instr, // Ignored for UART (data access only)
	input  wire [31:0] mem_addr,
	input  wire [31:0] mem_wdata,
	input  wire [ 3:0] mem_wstrb,
	output wire [31:0] mem_rdata,
	output wire        mem_ready,
	input  wire        is_uart_access,

	// External UART pins
	output wire        stx_pad_o,
	input  wire        srx_pad_i,
	output wire        rts_pad_o,
	input  wire        cts_pad_i
);

//---------------------------------------//
// Wishbone interface signals for UART  //
//---------------------------------------//
wire wb_rst;
wire wb_cyc;
wire wb_stb;
wire wb_we;
wire [4:0] wb_adr;
wire [31:0] wb_dat_i;
wire [31:0] wb_dat_o_uart;
wire [3:0] wb_sel;
wire wb_ack;

//--------------------------------//
// RX synchronization registers  //
//--------------------------------//
wire srx_sync_2;

//----------------------------------//
// Native-to-UART signal mapper
//----------------------------------//
soc_uart_wishbone_signal_mapper soc_uart_wishbone_signal_mapper (
	.sync_core_resetn(sync_core_resetn),
	.mem_valid(mem_valid),
	.mem_addr(mem_addr),
	.mem_wdata(mem_wdata),
	.mem_wstrb(mem_wstrb),
	.is_uart_access(is_uart_access),
	.wb_dat_o_uart(wb_dat_o_uart),
	.wb_ack(wb_ack),

	.wb_rst(wb_rst),
	.wb_cyc(wb_cyc),
	.wb_stb(wb_stb),
	.wb_we(wb_we),
	.wb_adr(wb_adr),
	.wb_dat_i(wb_dat_i),
	.wb_sel(wb_sel),
	.mem_rdata(mem_rdata),
	.mem_ready(mem_ready)
);

//----------------------------------//
// RX input synchronizer
//----------------------------------//
soc_uart_rx_input_synchronizer soc_uart_rx_input_synchronizer (
	.clk(clk),
	.srx_pad_i(srx_pad_i),
	.srx_sync_2(srx_sync_2)
);

//----------------------------------//
// UART instance
//----------------------------------//
uart_top uart_inst (
	.wb_clk_i(clk),
	.wb_rst_i(wb_rst),
	.wb_adr_i(wb_adr),
	.wb_dat_i(wb_dat_i),
	.wb_dat_o(wb_dat_o_uart),
	.wb_we_i(wb_we),
	.wb_stb_i(wb_stb),
	.wb_cyc_i(wb_cyc),
	.wb_ack_o(wb_ack),
	.wb_sel_i(wb_sel),
	.int_o(), // Interrupt output (connect to PLIC/CPU if needed)
	.stx_pad_o(stx_pad_o),
	.srx_pad_i(srx_sync_2), // Use synchronized RX input
	.rts_pad_o(rts_pad_o),
	.cts_pad_i(cts_pad_i), // Clear To Send = active
	.dtr_pad_o(),
	.dsr_pad_i(1'b0),
	.ri_pad_i(1'b1),
	.dcd_pad_i(1'b0)
);

endmodule