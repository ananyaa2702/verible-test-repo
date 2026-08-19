`timescale 1ns / 1ps
///////////////////////////////////////////////////////////////////////////////////////
// Engineer: Tanish A Shet, Samyak Nidhi, Shashank Tiwari
// Create Date: 28.03.2026
// Module Name: UART_loader_subsystem
// Project Name: Silicon SoC KNN
// Description:
// This module integrates the UART loader and UART receiver subsystems to facilitate
// firmware loading into the SRAM via UART. It manages the control signals and data flow
// between the two subsystems, ensuring proper synchronization and handling of the firmware
// loading process. The UART loader is responsible for processing the incoming data and
// generating the appropriate control signals for writing to SRAM, while the UART receiver
// handles the actual reception of data from the UART interface and provides it to the loader.
//////////////////////////////////////////////////////////////////////////////////////

module UART_loader_subsystem
#(
        parameter       W = 32,
        parameter       N = 14
)(
        input           clk,
        input           resetn_in,
        input           UART_load_en,
        input           i_rx,
        output          UART_load_done,
        output [W-1:0]  UART_SRAM_WDATA,
        output [N-1:0]  UART_SRAM_ADDR,
        output          UART_load_busy,
        output          o_rts,
        output          UART_check_start,
        output          o_rx_error,
        output          header_fail,

        // BRAM IP Specific Interfacing Signals
        output          sram_valid_uart, // BRAM IP SPECIFIC
        output          sram_wea_uart // BRAM IP SPECIFIC
);

wire word_read_done;
wire [W-1:0] word_rd_data;
wire UART_rd_en;

//---------------------------//
//UART_loader module instance//
//---------------------------//
UART_loader #(
	.N(N),
	.W(W)
) u_uart_loader (
        .clk (clk),
        .resetn_in (resetn_in),
        .UART_load_en (UART_load_en),
        .UART_load_done(UART_load_done),
        .UART_SRAM_WDATA(UART_SRAM_WDATA),
        .UART_SRAM_ADDR (UART_SRAM_ADDR),
        .UART_load_busy (UART_load_busy),
        .word_read_done (word_read_done),
        .UART_rdata(word_rd_data),
        .UART_rd_en(UART_rd_en),
        .UART_check_start(UART_check_start),
        .sram_valid_uart(sram_valid_uart), // BRAM IP SPECIFIC
        .sram_wea_uart(sram_wea_uart), // BRAM IP SPECIFIC
        .header_fail(header_fail) // Output header fail flag
);

//---------------------------------//
//uart_rx_subsystem module instance//
//---------------------------------//
uart_rx_subsystem u_uart_rx_subsystem (
        .i_clk (clk),
        .i_rst_n(resetn_in),
        .UART_rd_en (UART_rd_en),
        .o_word_data(word_rd_data),
        .o_rts (o_rts),
        .word_read_done(word_read_done),
        .i_rx(i_rx),
        .o_rx_error(o_rx_error)
);

endmodule