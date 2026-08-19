`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Shashank Tiwari, Samyak Nidhi, Tanish A Shet
// Create Date: 28.03.2026
// Module Name: uart_rx_subsystem
// Project Name: Silicon SoC KNN
// Description:
// Top-level UART receive datapath. Instantiates the uart_rx_fifo_wrapper to
// recover serial bytes, exposes hardware flow control, and feeds the byte_acc
// word assembler so firmware can fetch aligned 32-bit words alongside
// word-complete strobes and sticky RX error reporting.
//////////////////////////////////////////////////////////////////////////////////

module uart_rx_subsystem (
        input         i_clk,
        input         i_rst_n,
        input         i_rx,
        input         UART_rd_en,
        output [31:0] o_word_data,
        output        o_rts,
        output        word_read_done,
        output        o_rx_error

);

//-----------------//
// UART RX signals //
//-----------------//
wire [7:0] rx_byte;
wire fifo_empty;
wire rx_req;

//-----------------=---//
// Instantiate UART RX //
//---------------------//
uart_rx_fifo_wrapper uart_rx_fifo_u (
        .i_clk (i_clk),
	.i_rst_n (i_rst_n),
	.o_rx_data (rx_byte),
	.i_rx_req (rx_req),
	.o_fifo_empty (fifo_empty),
	.o_rx_error (o_rx_error),
	.i_rx (i_rx),
	.o_rts (o_rts)
);

//------------------------------//
// Instantiate byte accumulator //
//------------------------------//
byte_acc byte_acc_u (
	.i_clk (i_clk),
	.i_rst_n (i_rst_n),
	.UART_rd_en (UART_rd_en),
	//RX FIFO (8-bit) interface
	.i_fifo8_rd_data (rx_byte),
	.i_fifo8_empty (fifo_empty),
	.o_fifo8_rd_en (rx_req),
	.i_rx_error (o_rx_error),
	// Word output
	.o_fifo_word (o_word_data),
	.word_read_done (word_read_done)

);

endmodule
