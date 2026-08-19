`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Shashank Tiwari, Samyak Nidhi, Tanish A Shet, Rakesh Patil
// Last Modified: 03.04.2026
// Module Name: SRAM_CSR_logic
// Project Name: Silicon SoC KNN
// Description:
// CSR status register and boot control logic for SRAM interface.
// Manages CSR read/write transactions, boot load status, and ready signaling.
//////////////////////////////////////////////////////////////////////////////////

module SRAM_CSR_logic
(
	input  wire        clk,
	input  wire        resetn,
	input  wire [31:0] mem_wdata,
	input  wire [3:0]  mem_wstrb, // Active when writing to SRAM CSR
	input  wire        SRAM_CSR_Valid, // Active when accessing SRAM CSR address
	input  wire        boot_en, // Active when boot_controller is loading firmware to SRAM (flash -> core)

	output reg  [31:0] CSR_rdata, // Data read from CSR
	output wire         SRAM_CSR_ready, // Indicates data is ready
	output reg         load_done_core, // Active when firmware load is complete
	output reg         load_busy_core // Active during firmware load
);

//----------------------------------//
// Intermediate internal signals
//----------------------------------//
reg SRAM_CSR_ready_reg;
reg next_SRAM_CSR_ready;
reg [31:0] SRAM_STATUS_CSR;
wire mem_write;
reg [31:0] mem_wdata_d;
reg        mem_write_d;

/*
 * SRAM status CSR write path.
 * Captures write strobes and data, then updates SRAM_STATUS_CSR when
 * SRAM_CSR_Valid is asserted with a registered write request.
 */
always @(posedge clk)
begin
	if (!resetn)
	begin
		SRAM_STATUS_CSR <= 32'b0;
		mem_wdata_d <= 32'b0;
		mem_write_d <= 1'b0;
	end
	else
	begin
		// Delay write payload by one cycle to line up with registered SRAM_CSR_Valid.
		mem_wdata_d <= mem_wdata;
		mem_write_d <= mem_write;

		// CSR write via decoded valid signal from top-level address map.
		if (SRAM_CSR_Valid && mem_write_d)
			SRAM_STATUS_CSR <= mem_wdata_d;
	end
end

/*
 * Boot load status generation.
 * Asserts load_busy_core while boot flow is active and sets load_done_core
 * when CSR reports completion value 32'h0000_0004.
 */
always @(posedge clk)
begin
	if (!resetn)
	begin
		load_busy_core <= 1'b0;
		load_done_core <= 1'b0;
	end
	else
	begin
		if (boot_en)
		begin
			if (SRAM_STATUS_CSR == 32'h0000_0004)
			begin
				load_busy_core <= 1'b0;
				load_done_core <= 1'b1; // Set load_done only during boot-flash flow
			end
			else
			begin
				load_busy_core <= 1'b1;
				load_done_core <= 1'b0;
			end
		end
		else
		begin
			load_done_core <= 1'b0; // Clear load_done when not done
			load_busy_core <= 1'b0;
		end
	end
end

/*
 * CSR ready flag register.
 * Registers combinational ready intent to generate SRAM_CSR_ready output.
 */
always @(posedge clk)
begin
	if (!resetn)
		SRAM_CSR_ready_reg <= 1'b0;
	else
		SRAM_CSR_ready_reg <= next_SRAM_CSR_ready;
end

/*
 * CSR read mux and ready intent.
 * Returns SRAM_STATUS_CSR on CSR reads and drives ready when CSR space is accessed.
 */
always @(*)
begin
	CSR_rdata = 32'b0;
	if (SRAM_CSR_Valid)
	begin
		next_SRAM_CSR_ready = 1'b1;
		if (!mem_write)
			CSR_rdata = SRAM_STATUS_CSR;
	end
	else
	begin
		CSR_rdata = 32'b0;
		next_SRAM_CSR_ready = 1'b0;
	end
end

// Continuous assignments
assign mem_write = |mem_wstrb; // Any active write strobe indicates a write operation
assign SRAM_CSR_ready = SRAM_CSR_ready_reg;

endmodule
