`timescale 1ns / 1ps

///////////////////////////////////////////////////////////////////////////////////////////////////
// Engineer: Rakesh Patil, Shashank Tiwari, Samyak Nidhi
// Update Date: 10.04.2026
// Module Name: core_intermediate.v
// Project Name: Silicon SoC kNN
// Description:
// Extracted combinational helper block for core reset gating, SRAM window decode enable,
// and PicoRV32 auxiliary constant tie-offs.
///////////////////////////////////////////////////////////////////////////////////////////////////

module core_intermediate #(
        parameter [31:0] SRAM_REG_START = 32'h0600_0000,
        parameter [31:0] SRAM_REG_END   = 32'h0600_3FFC
) (
        input wire sync_core_resetn,
        input wire mem_valid,
        input wire [31:0] mem_addr,
        output wire pcpi_wr,
        output wire [31:0] pcpi_rd,
        output wire pcpi_wait,
        output wire pcpi_ready,
        output wire [31:0] irq,
        output wire [31:0] eoi,
        output wire trace_valid,
        output wire [35:0] trace_data,
        output wire core_resetn,
        output wire core_decoder_en
);

assign core_resetn = sync_core_resetn;

assign pcpi_wr = 1'b0;
assign pcpi_rd = 32'b0;
assign pcpi_wait = 1'b0;
assign pcpi_ready = 1'b0;
assign irq = 32'b0;
assign eoi = 32'b0;
assign trace_valid = 1'b0;
assign trace_data = 36'b0;

/*
 * Enable SRAM decode only for CPU data accesses within the SRAM window.
 */
assign core_decoder_en = mem_valid && ((mem_addr >= SRAM_REG_START) && (mem_addr <= SRAM_REG_END));

endmodule
