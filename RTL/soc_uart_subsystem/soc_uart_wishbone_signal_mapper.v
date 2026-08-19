`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Shashank Tiwari, Samyak Nidhi, Tanish A Shet, Rakesh Patil
// Last Modified: 03.04.2026
// Module Name: soc_uart_wishbone_signal_mapper
// Project Name: Silicon SoC KNN
// Description:
// Combinational logic block that maps native memory-interface transactions
// to UART Wishbone control/data signals and returns read/ready responses.
//////////////////////////////////////////////////////////////////////////////////

module soc_uart_wishbone_signal_mapper
(
	input  wire        sync_core_resetn,
	input  wire        mem_valid,
	input  wire [31:0] mem_addr,
	input  wire [31:0] mem_wdata,
	input  wire [ 3:0] mem_wstrb,
	input  wire        is_uart_access,
	input  wire [31:0] wb_dat_o_uart,
	input  wire        wb_ack,

	output wire        wb_rst,
	output wire        wb_cyc,
	output wire        wb_stb,
	output wire        wb_we,
	output reg  [4:0]  wb_adr,
	output wire [31:0] wb_dat_i,
	output reg  [3:0]  wb_sel,
	output wire [31:0] mem_rdata,
	output wire        mem_ready
);

//----------------------------------//
// Intermediate internal signals
//----------------------------------//
reg [31:0] aligned_data;

//----------------------------------//
// Address and byte-lane steering
//----------------------------------//
always @(*)
begin
	if (wb_we)
	begin
		wb_adr = mem_addr[4:0];
		wb_sel = mem_wstrb;
	end
	else
	begin
		case (mem_addr[7:0])
			8'h08:
			begin
				wb_adr = 5'h04;
				wb_sel = 4'b0001;
			end
			8'h0C:
			begin
				wb_adr = 5'h05;
				wb_sel = 4'b0010;
			end
			8'h10:
			begin
				wb_adr = 5'h06;
				wb_sel = 4'b0100;
			end
			default:
			begin
				wb_adr = mem_addr[4:0];
				wb_sel = 4'b0001;
			end
		endcase
	end
end

//----------------------------------//
// Read-data byte-lane steering
//----------------------------------//
always @(*)
begin
	case (wb_sel)
		4'b0001: aligned_data = {24'b0, wb_dat_o_uart[7:0]};
		4'b0010: aligned_data = {24'b0, wb_dat_o_uart[15:8]};
		4'b0100: aligned_data = {24'b0, wb_dat_o_uart[23:16]};
		4'b1000: aligned_data = {24'b0, wb_dat_o_uart[31:24]};
		default: aligned_data = wb_dat_o_uart;
	endcase
end

// Reset mapping to UART wrapper active-high reset.
assign wb_rst = sync_core_resetn;

// Cycle and strobe assert only when UART access is selected.
assign wb_cyc = mem_valid && is_uart_access;
assign wb_stb = mem_valid && is_uart_access;

// Write enable is driven by byte strobe activity.
assign wb_we = (mem_wstrb != 4'b0000);

// Data mappings to UART interface.
assign wb_dat_i = mem_wdata;

// Handshake return from UART.
// mem_ready is asserted only for selected UART accesses when wb_ack is high.
assign mem_ready = wb_ack && is_uart_access;

// Read-data muxing for selected UART transactions.
// Drive zero when this block is not selected.
assign mem_rdata = is_uart_access ? aligned_data : 32'b0;

endmodule
