`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Shashank Tiwari, Samyak Nidhi
// Last Modified: 03.04.2026
// Module Name: core_bootrom_remap
// Project Name: Silicon SoC KNN
// Description:
// Generates remap enable for BootROM accesses when backup mode is active.
// In normal mode, remap is disabled; in backup mode, accesses within the
// BootROM address range assert core_decoder_en_remap.
//////////////////////////////////////////////////////////////////////////////////

module core_bootrom_remap
#(
	parameter BOOTROM_REG_START = 32'h0000_0000,
	parameter BOOTROM_REG_END = 32'h0000_3FFC
)(
	input  wire [1:0]  mode_sel,
	input  wire [31:0] mem_addr,
	input  wire        mem_valid,
	output reg         core_decoder_en_remap
);

/*
 * BootROM remap decode logic.
 * Disable remap in normal mode. In backup mode, assert remap only when
 * the incoming address falls within the BootROM region.
 */

 /*
  *unsafe as mode_sel condition is 1 but mem_addr is x (since data path always left at x to save power)
  * but 1 && x is not 1 it is x hence else if fails but else also not picked, core_decoder_en_remap
  * becomes x
 */
always @(*)
begin
	core_decoder_en_remap = 1'b0;

    	// Only evaluate address if the transaction is actually valid
    	if ((mode_sel != 2'b00) && mem_valid)
	begin
        	if ((mem_addr >= BOOTROM_REG_START) && (mem_addr <= BOOTROM_REG_END))
            core_decoder_en_remap = 1'b1;
	end
end

endmodule