`timescale 1ns / 1ps
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Engineer: Shashank Tiwari, Samyak Nidhi, Tanish A Shet
// Update Date: 29.03.2026
// Module Name: SRAM Controller
// Project Name: Silicon SoC KNN
//
// Description:
// Top level wrapper module integrating
// 1) boot_controller
// 2) reset_controller
// 3) CORE- reset signals
// 4) UART_loader_subsystem - for loading firmware to SRAM from UART.
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

`define ENABLE_UART_LOADER
//`define ENABLE_FIFO_LOADER

module SRAM_controller
#(
	parameter N = 14,
	parameter W = 32
)(
	input clk,
	input resetn_in,
	input load_en,
	input i_rx,
	input [1:0] mode_sel,

   	//Signals from Core
   	input wire load_busy_core, // Active when flash -> core -> SRAM load is in progress
   	input wire load_done_core, // Active when flash -> core -> SRAM load is done
   	input wire [W-1:0] CORE_WDATA,
   	input wire [31:0] CORE_ADDR,

   	//Signals to Core
   	output wire sync_core_resetn, // Synchronous reset to core (active low)
   	output wire boot_en, // Active during firmware loading (flash -> core -> SRAM)

   	//Signals to address decoder
   	output wire [31:0] SRAM_ADDR_RAW, // Raw address to SRAM (before any address translation)
   	output wire fw_load_en,

   	//Signals to SRAM (after MUX selection)
   	output wire [31:0] SRAM_WDATA, // Final write data to SRAM

   	// Flags and status outputs
   	output load_busy,
   	output load_done,
   	output o_rts,
   	output UART_check_start,
   	output UART_rx_error,
   	output header_fail,

   	// BRAM IP Specific Interfacing Signals
   	output sram_valid_uart,
   	output sram_wea_uart
);



//---------------------------------------------//
// Intermediate Address and Write Data Signals //
//---------------------------------------------//
wire [31:0] FW_ADDR; // Final FW based address to SRAM after MUX selection from mode_sel
wire [W-1:0] FW_WDATA; // Final FW based write data to SRAM after MUX selection from mode_sel

//-----------------------------------//
// Reset Controller Internal Signals //
//-----------------------------------//
wire resetn_core_req;

//---------------------//
// UART Loader Signals //
//---------------------//
wire UART_rx_enable;
wire UART_ld_done;
wire UART_load_busy;
wire [W-1:0] UART_SRAM_WDATA;
wire [31:0] UART_SRAM_ADDR;

//---------------------//
// FIFO Loader Signals //
//---------------------//
`ifdef ENABLE_FIFO_LOADER

wire FIFO_rx_en;
wire FIFO_ld_done;
wire FIFO_load_busy;
wire [W-1:0] FIFO_SRAM_WDATA;
wire [31:0] FIFO_SRAM_ADDR;

`else

// Stub signals when FIFO not enabled
wire FIFO_rx_en;
wire FIFO_ld_done = 1'b0;
wire FIFO_load_busy = 1'b0;
wire [W-1:0] FIFO_SRAM_WDATA = {W{1'b0}};
wire [31:0] FIFO_SRAM_ADDR = {W{1'b0}};

`endif

//---------------------------//
// controller_path_mux inst  //
//---------------------------//
controller_path_mux #(
	.N(N),
	.W(W)
) u_controller_path_mux (
	.mode_sel(mode_sel),
	.fw_load_en(fw_load_en),
	.CORE_WDATA(CORE_WDATA),
	.CORE_ADDR(CORE_ADDR),
	.UART_SRAM_WDATA(UART_SRAM_WDATA),
	.UART_SRAM_ADDR(UART_SRAM_ADDR),
	.FIFO_SRAM_WDATA(FIFO_SRAM_WDATA),
	.FIFO_SRAM_ADDR(FIFO_SRAM_ADDR),
	.FW_ADDR(FW_ADDR),
	.FW_WDATA(FW_WDATA),
	.SRAM_ADDR_RAW(SRAM_ADDR_RAW),
	.SRAM_WDATA(SRAM_WDATA)
);

//----------------------------//
// boot_controller.v instance //
//----------------------------//
boot_controller u_boot_ctrl (
	.clk(clk),
   	.resetn_in(resetn_in),
   	.load_en(load_en),
   	.mode_sel(mode_sel),

   	// UART signals (stub when disabled)
   	.UART_load_done(UART_ld_done),
   	.UART_load_busy(UART_load_busy),
   	.UART_rx_en(UART_rx_enable),

   	// FIFO signals (stub when disabled)
   	.FIFO_load_done(FIFO_ld_done),
   	.FIFO_load_busy(FIFO_load_busy),
   	.FIFO_rx_en(FIFO_rx_en),

   	// Boot signals (stub when disabled)
   	.boot_load_done(load_done_core),
   	.boot_load_busy(load_busy_core),
   	.boot_en(boot_en),

   	// Outputs
   	.resetn_core_req(resetn_core_req),
   	.fw_load_en(fw_load_en),
   	.load_done(load_done),
   	.load_busy(load_busy)
);

//---------------------------//
// UART loader instance      //
//---------------------------//
`ifdef ENABLE_UART_LOADER

UART_loader_subsystem #(
	.W(W),
	.N(N)
) u_uart_loader_subsystem (
	.clk(clk),
	.resetn_in(resetn_in),
	.UART_load_en(UART_rx_enable),
	.i_rx(i_rx),
	.UART_load_done(UART_ld_done),
	.UART_SRAM_WDATA(UART_SRAM_WDATA),
	.UART_SRAM_ADDR(UART_SRAM_ADDR),
	.UART_load_busy(UART_load_busy),
	.o_rts(o_rts),
	.o_rx_error(UART_rx_error),
	.UART_check_start(UART_check_start),
	.sram_valid_uart(sram_valid_uart), // BRAM IP SPECIFIC
	.sram_wea_uart(sram_wea_uart), // BRAM IP SPECIFIC
	.header_fail(header_fail)
);

`else

assign UART_ld_done = 1'b0;
assign UART_load_busy = 1'b0;
assign o_rts = 1'b0;
assign UART_rx_error = 1'b0;
assign UART_check_start = 1'b0;

`endif

//---------------------------//
// FIFO loader instance      //
//---------------------------//
`ifdef ENABLE_FIFO_LOADER

/*
 * TODO:
 * Instantiate FIFO_loader_subsystem when implemented
*/

`endif

//---------------------------//
//reset_controller.v instance//
//---------------------------//
reset_controller u_resetn_ctrl (
	.clk(clk),
	.resetn_in(resetn_in),
	.resetn_core_req(resetn_core_req),
	.sync_core_resetn(sync_core_resetn)
);

endmodule
