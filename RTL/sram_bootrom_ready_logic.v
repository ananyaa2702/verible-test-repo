`timescale 1ns / 1ps

///////////////////////////////////////////////////////////////////////////////////////////////////
// Engineer: Rakesh Patil, Shashank Tiwari, Samyak Nidhi
// Update Date: 03.04.2026
// Module Name: sram_bootrom_ready_logic.v
// Project Name: Silicon SoC kNN
// Description:
// Ready/valid glue logic for BootROM and SRAM paths.
// Generates BootROM decode, one-cycle ready timing, and merged SRAM valid/write-enable signals.
///////////////////////////////////////////////////////////////////////////////////////////////////

module sram_bootrom_ready_logic #(
        parameter [31:0] BOOTROM_REG_START = 32'h0000_0000,
        parameter [31:0] BOOTROM_REG_END   = 32'h0000_3FFC
) (
        input wire clk,
        input wire resetn,
        input wire mem_valid,
        input wire [1:0] mode_sel,
        input wire [31:0] mem_addr,
        input wire sram_valid_core,
        input wire sram_wea_core,
        input wire sram_wea_uart,
        input wire sram_valid_uart,
        output wire bootrom_valid,
        output reg bootrom_ready,
        output reg sram_ready,
        output wire sram_wea,
        output wire sram_valid
);

/*
 * Register the BootROM ready response.
 * This block mirrors the BootROM valid signal by one clock to form the
 * BRAM-style ready indication used by the core.
 */
always @(posedge clk)
begin
        if (!resetn)
                bootrom_ready <= 1'b0;
        else
                bootrom_ready <= bootrom_valid;
end

/*
 * Register the SRAM ready response.
 * This block delays the core SRAM valid signal by one clock so the SRAM
 * BRAM path presents the expected ready timing.
 */
always @(posedge clk)
begin
        if (!resetn)
                sram_ready <= 1'b0;
        else
                // We only need valid signal when core is accessing SRAM
                sram_ready <= sram_valid_core;
end

// Write enable when either core or UART is writing to SRAM
assign sram_wea = sram_wea_core || sram_wea_uart;

// Valid when either core or UART is accessing SRAM
assign sram_valid = sram_valid_core || sram_valid_uart;

/*
 * BootROM is selected only during core boot mode and when the access falls
 * inside the BootROM address window.
 */
assign bootrom_valid = (mem_valid === 1'b1) && (mode_sel == 2'b00) && (mem_addr >= BOOTROM_REG_START) && (mem_addr <= BOOTROM_REG_END);


endmodule
