`timescale 1ns / 1ps
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Engineer: Shashank Tiwari, Samyak Nidhi, Tanish A Shet
// Update Date: 27.03.2026
// Module Name: controller_path_mux
// Project Name: Silicon SoC KNN
//
// Description:
// Standalone combinational block that selects firmware loading sources based on mode_sel
// and generates the SRAM address/data presented to the decoder. This module was
// factored out from SRAM_controller so that the top-level wrapper only contains
// structural instance wiring.
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

module controller_path_mux
#(
	parameter               N = 14,
	parameter               W = 32
)(
	input [1:0]             mode_sel,
	input                   fw_load_en,
	input [W-1:0]           CORE_WDATA,
	input [31:0]            CORE_ADDR,
	input [W-1:0]           UART_SRAM_WDATA,
	input [31:0]           UART_SRAM_ADDR,
	input [W-1:0]           FIFO_SRAM_WDATA,
	input [31:0]           FIFO_SRAM_ADDR,
	output reg [31:0]      FW_ADDR,
	output reg [W-1:0]      FW_WDATA,
	output [31:0]           SRAM_ADDR_RAW,
	output [31:0]           SRAM_WDATA
);

/*
 * This combinational block implements the MUX logic to select between different
 * firmware loading sources (UART, FIFO, or direct from core) based on mode_sel
 * input. The selected address and data are then forwarded to the SRAM interface.
 */
always @(*) begin
	case (mode_sel)
		2'b10:
                begin
 			FW_WDATA = UART_SRAM_WDATA;
			FW_ADDR = {{(32-N){1'b0}},UART_SRAM_ADDR};
      		end
      		2'b01:
                begin
			FW_WDATA = FIFO_SRAM_WDATA;
			FW_ADDR = {{(32-N){1'b0}},FIFO_SRAM_ADDR};
      		end
      		2'b00:
                begin
			FW_WDATA = CORE_WDATA;
			FW_ADDR  = CORE_ADDR; // As Bus width of SRAM_ADDR is N
      		end
      		default:
                begin
 			FW_WDATA = {W{1'b0}};
 			FW_ADDR  = {W{1'b0}};
		end
   	endcase
end

/*
 * Address to SRAM is selected either from the backup path
 * or the core path during firmware loading phase.
 */
assign SRAM_ADDR_RAW = fw_load_en ? FW_ADDR : CORE_ADDR;

/*
 * Similar to address selction above, the write data to SRAM is selected
 * based on backup path or core path during firmware loading phase.
 */
assign SRAM_WDATA = fw_load_en ? FW_WDATA : CORE_WDATA;


endmodule
