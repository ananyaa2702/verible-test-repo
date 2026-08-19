`timescale 1ns / 1ps
///////////////////////////////////////////////////////////////////////////////////////////////////
// Engineer: Shashank Tiwari, Samyak Nidhi, Tanish A Shet
// Update Date: 27.03.2026
// Module Name: Address Decoder
// Project Name: Silicon SoC KNN
//
// Description:
// This module implements the address decoding logic for the SRAM controller.
// It takes the raw address input from either the core or the firmware loading path
// and translates it into the appropriate address format for accessing the SRAM.
// The decoder also generates enable signals to select between core access and firmware
// loading access based on the mode of operation. The output address is word-aligned and
// is only driven when either the core is accessing or firmware loading is active,
// otherwise it is tri-stated to prevent unintentional accesses to the SRAM.
///////////////////////////////////////////////////////////////////////////////////////////////////

module addr_decoder
#(
	parameter       N = 14
)(
	input           fw_load_en,
	input           core_decoder_en,
	input           core_decoder_en_remap, // Read enable signal for remapped BootROM access in backup mode
	input [1:0]     mode_sel, // Select between normal mode and backup mode
	input [31:0]    SRAM_ADDR_RAW,
	output [N-1:0]  SRAM_ADDR // Translated final SRAM address
);



wire output_en; // Enable SRAM address line else tri-state
wire decode_en; // Enable Byte-Address to Word-Address Translation
wire [N-1:0] ADDR_reg_core;
wire [N-1:0] ADDR_reg_fw;

assign decode_en = (core_decoder_en || core_decoder_en_remap) ? 1'b1 : 1'b0;

// Active when either FW loading or Core accessing
assign output_en = fw_load_en | decode_en;

// Byte-Aligned to Word-Aligned address translation
assign ADDR_reg_core = SRAM_ADDR_RAW[N+1:2];

// FW address: use lower N bits directly (already 12-bit from FW path)
	assign ADDR_reg_fw = (mode_sel == 2'b00) ? SRAM_ADDR_RAW[N+1:2] : SRAM_ADDR_RAW[N-1:0];

// Output tri-state when neither FW loading nor CORE accessing
assign SRAM_ADDR = output_en ? (decode_en ? (ADDR_reg_core) : ADDR_reg_fw) : {N{1'b0}};

endmodule
