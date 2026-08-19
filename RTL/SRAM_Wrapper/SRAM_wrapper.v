`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Shashank Tiwari, Samyak Nidhi
// Last Modified: 03.04.2026
// Module Name: SRAM_wrapper
// Project Name: Silicon SoC KNN
// Description:
// Wrapper for SRAM access, selecting between FPGA BRAM IP and ASIC SPRAM macro
// based on synthesis context. Provides dual-flow instantiation without internal logic.
// DUAL FLOW IMPLEMENTATION:
// - FOR_FPGA (synthesis): Uses blk_mem_gen_1 (Xilinx BRAM core) for efficient FPGA
//   resource usage. SPRAM_8192x36 macro is preprocessor-excluded (not synthesized).
// - ASIC (non-synthesis): Uses SCL180nm SPRAM_8192x36 macro for silicon implementation.
//   Xilinx BRAM core is preprocessor-excluded.
//   Data output is masked to 32 bits (parity bits stripped). WEB/OEB/CSB are active-LOW.
//////////////////////////////////////////////////////////////////////////////////

// Uncomment for ASIC Cadence
// `include "global_defines.v"

module SRAM_wrapper #(
        parameter N = 14
)(
        input  wire        clk,
        input  wire        resetn,
        input  wire        sram_wea,
        input  wire [31:0] SRAM_WDATA,
        input  wire        sram_valid, // Active when accessing SRAM address range
        input  wire [N-1:0]SRAM_ADDR,

        // SRAM outputs
        output wire [31:0] SRAM_RDATA
);

//----------------------------------//
// FPGA BRAM instantiation
//----------------------------------//
`ifdef FOR_FPGA
blk_mem_gen_1 sram(
	.clka(clk),
	.rsta(~resetn),
	.ena(sram_valid),
	.wea(sram_wea),
	.addra(SRAM_ADDR),
	.dina(SRAM_WDATA),
	.douta(SRAM_RDATA)
);
`endif

//----------------------------------//
// ASIC SPRAM instantiation
//----------------------------------//

`ifdef FOR_SPRAM
wire [35:0] sram_dataout_36;

SRAM_addr_virtualisation #(
	.N(N)
) u_sram_addr_virtualisation (
	.clk(clk),
	.sram_wea(sram_wea),
	.sram_valid(sram_valid),
	.SRAM_ADDR(SRAM_ADDR),
	.SRAM_WDATA(SRAM_WDATA),
	.sram_dataout_36(sram_dataout_36)
);

// Strip parity bits (top 4) and extract 32-bit data.
assign SRAM_RDATA = sram_dataout_36[31:0];

`endif

endmodule
