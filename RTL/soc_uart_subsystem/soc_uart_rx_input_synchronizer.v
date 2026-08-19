`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Shashank Tiwari, Samyak Nidhi, Tanish A Shet, Rakesh Patil
// Last Modified: 03.04.2026
// Module Name: soc_uart_rx_input_synchronizer
// Project Name: Silicon SoC KNN
// Description:
// Two-flop synchronizer for the asynchronous external UART RX input before it
// is connected to the UART core receive pin.
//////////////////////////////////////////////////////////////////////////////////

module soc_uart_rx_input_synchronizer
(
	input  wire clk,
	input  wire srx_pad_i,
	output wire srx_sync_2
);

//----------------------------------//
// Intermediate internal signals
//----------------------------------//
reg srx_sync_1;
reg srx_sync_2_reg;

//----------------------------------//
// RX input synchronization logic
//----------------------------------//
always @(posedge clk)
begin
	srx_sync_1 <= srx_pad_i;
	srx_sync_2_reg <= srx_sync_1;
end

assign srx_sync_2 = srx_sync_2_reg;

endmodule
