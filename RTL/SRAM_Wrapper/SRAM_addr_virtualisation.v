`timescale 1ns / 1ps
///////////////////////////////////////////////////////////////////////////////////////////////////
// Engineer: Shashank Tiwari, Samyak Nidhi, Siddhanth Ganapathi
// Last Modified: 03.04.2026
// Module Name: SRAM_wrapper
// Project Name: Silicon SoC KNN
// Description:
// 4 SPRAM_2048x36 macros and 2 SPRAM_1024x36 macros are instantiated to form a 10240x36 SRAM.
// Address range of the full SRAM is 0x0600_0000 to 0x0600_27FC. This address range is
// split into 4 equal parts, each part is mapped to one of the 4 SPRAM_2048x36 macros.
// The remaining address range is split into 2 equal parts, each part is mapped to one of the
// 2 SPRAM_1024x36 macros. Thus software sees 10240x36 SRAM, but in reality, it is implemented
// using 4 SPRAM_2048x36 macros and 2 SPRAM_1024x36 macros.
////////////////////////////////////////////////////////////////////////////////////////////////////

module SRAM_addr_virtualisation #(
	parameter N = 14
)(
	input clk,
	input sram_wea,
	input sram_valid,
	input  wire [N-1:0] SRAM_ADDR,
	input  wire [31:0]  SRAM_WDATA,
	output reg [35:0] sram_dataout_36

);

reg [3:0] sram_sel;
wire [35:0] sram_dataout_36_0, sram_dataout_36_1, sram_dataout_36_2, sram_dataout_36_3, sram_dataout_36_4, sram_dataout_36_5;
reg [31:0] SRAM_WDATA_0, SRAM_WDATA_1, SRAM_WDATA_2, SRAM_WDATA_3, SRAM_WDATA_4, SRAM_WDATA_5;
reg [N-1:0] SRAM_ADDR_0, SRAM_ADDR_1, SRAM_ADDR_2, SRAM_ADDR_3, SRAM_ADDR_4, SRAM_ADDR_5;
reg [3:0] sram_sel_q;
always @(posedge clk)
begin
	sram_sel_q <= sram_sel;
end

/*
 * Combinational logic is used to virtualise the SRAM address space, essentially creating a MUX logic
 * to select the appropriate SPRAM_2048x36 and SPRAM_1024x36 macros based on the input address.
 */
always @(*)
begin
	sram_sel = 4'b1111;
	if (sram_valid)
	begin
		if (SRAM_ADDR >= 14'h0000 && SRAM_ADDR <= 14'h07FF)
			sram_sel = 4'b0000; // Select SPRAM_2048x36_0
		else if (SRAM_ADDR >= 14'h0800 && SRAM_ADDR <= 14'h0FFF)
			sram_sel = 4'b0001; // Select SPRAM_2048x36_1
		else if (SRAM_ADDR >= 14'h1000 && SRAM_ADDR <= 14'h17FF)
			sram_sel = 4'b0010; // Select SPRAM_2048x36_2
		else if (SRAM_ADDR >= 14'h1800 && SRAM_ADDR <= 14'h1FFF)
			sram_sel = 4'b0011; // Select SPRAM_2048x36_3
		else if (SRAM_ADDR >= 14'h2000 && SRAM_ADDR <= 14'h23FF)
			sram_sel = 4'b0100; // Select SPRAM_1024x36_0
		else if (SRAM_ADDR >= 14'h2400 && SRAM_ADDR <= 14'h27FF)
			sram_sel = 4'b0101; // Select SPRAM_1024x36_1
		else
			sram_sel = 4'b1111; // Invalid address range, no SPRAM selected
	end
	else
		sram_sel = 4'b1111; // No valid access, no SPRAM selected
end

always @(*)
begin
	SRAM_ADDR_0 = 14'h0;
	SRAM_ADDR_1 = 14'h0;
	SRAM_ADDR_2 = 14'h0;
	SRAM_ADDR_3 = 14'h0;
	SRAM_ADDR_4 = 14'h0;
	SRAM_ADDR_5 = 14'h0;
	SRAM_WDATA_0 = 32'h0;
	SRAM_WDATA_1 = 32'h0;
	SRAM_WDATA_2 = 32'h0;
	SRAM_WDATA_3 = 32'h0;
	SRAM_WDATA_4 = 32'h0;
	SRAM_WDATA_5 = 32'h0;
	sram_dataout_36 = 36'h0;

	case(sram_sel)
		4'b0000:
		begin
			SRAM_ADDR_0 = SRAM_ADDR;
			SRAM_WDATA_0 = SRAM_WDATA;
			//sram_dataout_36 = sram_dataout_36_0;
		end
		4'b0001:
		begin
			SRAM_ADDR_1 = SRAM_ADDR - 13'h800; // Offset for SPRAM_2048x36_1
			SRAM_WDATA_1 = SRAM_WDATA;
			//sram_dataout_36 = sram_dataout_36_1;
		end
		4'b0010:
		begin
			SRAM_ADDR_2 = SRAM_ADDR - 13'h1000; // Offset for SPRAM_2048x36_2
			SRAM_WDATA_2 = SRAM_WDATA;
			//sram_dataout_36 = sram_dataout_36_2;
		end
		4'b0011:
		begin
			SRAM_ADDR_3 = SRAM_ADDR - 14'h1800; // Offset for SPRAM_2048x36_3
			SRAM_WDATA_3 = SRAM_WDATA;
			//sram_dataout_36 = sram_dataout_36_3;
		end
		4'b0100:
		begin
			SRAM_ADDR_4 = SRAM_ADDR - 14'h2000; // Offset for SPRAM_1024x36_0
			SRAM_WDATA_4 = SRAM_WDATA;
			//sram_dataout_36 = sram_dataout_36_4;
		end
		4'b0101:
		begin
			SRAM_ADDR_5 = SRAM_ADDR - 14'h2400; // Offset for SPRAM_1024x36_1
			SRAM_WDATA_5 = SRAM_WDATA;
			//sram_dataout_36 = sram_dataout_36_5;
		end
		default:
		begin
			SRAM_ADDR_0 = 14'h0;
			SRAM_ADDR_1 = 14'h0;
			SRAM_ADDR_2 = 14'h0;
			SRAM_ADDR_3 = 14'h0;
			SRAM_ADDR_4 = 14'h0;
			SRAM_ADDR_5 = 14'h0;
			SRAM_WDATA_0 = 32'h0;
			SRAM_WDATA_1 = 32'h0;
			SRAM_WDATA_2 = 32'h0;
			SRAM_WDATA_3 = 32'h0;
			SRAM_WDATA_4 = 32'h0;
			SRAM_WDATA_5 = 32'h0;
			sram_dataout_36 = 36'h0;
		end
	endcase
	case(sram_sel_q)
		4'b0000: sram_dataout_36 = sram_dataout_36_0;
		4'b0001: sram_dataout_36 = sram_dataout_36_1;
		4'b0010: sram_dataout_36 = sram_dataout_36_2;
		4'b0011: sram_dataout_36 = sram_dataout_36_3;
		4'b0100: sram_dataout_36 = sram_dataout_36_4;
		4'b0101: sram_dataout_36 = sram_dataout_36_5;
		default: sram_dataout_36 = 36'h0;
	endcase
end

SPRAM_2048x36 sram_asic_0
(
	.A(SRAM_ADDR_0[10:0]),
	.CE(clk),
	.WEB(~(sram_valid && sram_wea && (sram_sel == 4'b0000))),
	.OEB(~(sram_valid && !sram_wea && (sram_sel == 4'b0000))),
	.CSB(~(sram_valid && (sram_sel == 4'b0000))),
	.I({4'b0000, SRAM_WDATA_0}),
	.O(sram_dataout_36_0)
);

SPRAM_2048x36 sram_asic_1
(
	.A(SRAM_ADDR_1[10:0]),
	.CE(clk),
	.WEB(~(sram_valid && sram_wea && (sram_sel == 4'b0001))),
	.OEB(~(sram_valid && !sram_wea && (sram_sel == 4'b0001))),
	.CSB(~(sram_valid && (sram_sel == 4'b0001))),
	.I({4'b0000, SRAM_WDATA_1}),
	.O(sram_dataout_36_1)
);

SPRAM_2048x36 sram_asic_2
(
	.A(SRAM_ADDR_2[10:0]),
	.CE(clk),
	.WEB(~(sram_valid && sram_wea && (sram_sel == 4'b0010))),
	.OEB(~(sram_valid && !sram_wea && (sram_sel == 4'b0010))),
	.CSB(~(sram_valid && (sram_sel == 4'b0010))),
	.I({4'b0000, SRAM_WDATA_2}),
	.O(sram_dataout_36_2)
);

SPRAM_2048x36 sram_asic_3
(
	.A(SRAM_ADDR_3[10:0]),
	.CE(clk),
	.WEB(~(sram_valid && sram_wea && (sram_sel == 4'b0011))),
	.OEB(~(sram_valid && !sram_wea && (sram_sel == 4'b0011))),
	.CSB(~(sram_valid && (sram_sel == 4'b0011))),
	.I({4'b0000, SRAM_WDATA_3}),
	.O(sram_dataout_36_3)
);

SPRAM_1024x36 sram_asic_4
(
	.A(SRAM_ADDR_4[9:0]),
	.CE(clk),
	.WEB(~(sram_valid && sram_wea && (sram_sel == 4'b0100))),
	.OEB(~(sram_valid && !sram_wea && (sram_sel == 4'b0100))),
	.CSB(~(sram_valid && (sram_sel == 4'b0100))),
	.I({4'b0000, SRAM_WDATA_4}),
	.O(sram_dataout_36_4)
);

SPRAM_1024x36 sram_asic_5
(
	.A(SRAM_ADDR_5[9:0]),
	.CE(clk),
	.WEB(~(sram_valid && sram_wea && (sram_sel == 4'b0101))),
	.OEB(~(sram_valid && !sram_wea && (sram_sel == 4'b0101))),
	.CSB(~(sram_valid && (sram_sel == 4'b0101))),
	.I({4'b0000, SRAM_WDATA_5}),
	.O(sram_dataout_36_5)
);

endmodule