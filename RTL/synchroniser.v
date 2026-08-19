`timescale 1ns / 1ps
///////////////////////////////////////////////////////////////////////////////////////////////////
// Engineer: Shashank Tiwari, Samyak Nidhi, Rohith Suju
// Update Date: 27.06.2026
// Module Name: synchroniser.v
// Project Name: Silicon SoC kNN
// Description:
// These module takes in all the asynchronous signals from outside the chip and synchronises them
// to the internal clock domain. It uses a 3-stage FF synchroniser for each signal to avoid
// metastability issues.
// List of signals synchronised:
// - load_en
// - mode_sel
//
// NOTE: load_en is internally recognised as a pulse so a slightly differnt synchronisation is used
// for it. Counter logic is definedn which samples just 1 switch (low to high) once every 10 ms.
///////////////////////////////////////////////////////////////////////////////////////////////////

module synchroniser #(
	parameter REFRESH_CYCLES = 1_000_000 // Number of clock cycles for 10 ms at 100 MHz
) (
	input wire 	  clk,
	input wire 	  resetn,
	input wire 	  load_en_async,
	input wire  [1:0] mode_sel_async,

	output wire 	  load_en,
	output wire [1:0] mode_sel
);

//-------------------------------//
// Internal Signals for mode_sel //
//-------------------------------//
reg [1:0] mode_sel1;
reg [1:0] mode_sel2;
reg [1:0] mode_sel3;

//------------------------------//
// Internal Signals for load_en //
//------------------------------//
reg load_en1;
reg load_en2;
reg load_en_prev;
reg [19:0] counter;
reg [19:0] counter_next;

/*
 * mode_sel signal is gray coded thus a 3-stage FF synchroniser can be used
 * to synchronise it to the internal clock domain. Mode_sel will not have
 * transitions such as 00 to 11.
 */
always @(posedge clk or negedge resetn)
begin
	if (!resetn)
	begin
		mode_sel1 <= 2'b00;
		mode_sel2 <= 2'b00;
		mode_sel3 <= 2'b00;
	end
	else
	begin
		mode_sel1 <= mode_sel_async;
		mode_sel2 <= mode_sel1;
		mode_sel3 <= mode_sel2;
	end
end

/*
 * Customised Synchronisation logic used for load_en signal.
 * A counter used to sample transitions 1 every 10ms.
 * This is done as in an external switch, ON to OFF transition due to metal pin
 * contact has multiple 0->1->0->1 transtions before settling to final value.
 */
always @(posedge clk or negedge resetn)
begin
	if (!resetn)
	begin
		load_en1 <= 0;
		load_en2 <= 0;
		load_en_prev <= 0;
		counter <= 20'd0;
	end
	else
	begin
		load_en1 <= load_en_async;
		load_en2 <= load_en1;

		load_en_prev <= load_en2;

		if (counter > 0)
			counter <= counter_next;
		else if (load_en)
			counter <= REFRESH_CYCLES;
		else
			counter <= 0;
	end
end

always@(*)
begin
	if(!resetn)
		counter_next = 0;
	else
		counter_next = counter - 1'b1;
end

/*
 * load_en_prev acts a way to only sample 1 0 -> 1 transition. This is used in the
 * assign along with load_en2 to catch the first 0 -> 1 tranistion then any sunsequent
 * 1 -> 0 or 0 -> 1 transitions are ignored for 10 ms.
 */
assign load_en = (load_en2 == 1'b1 && load_en_prev == 1'b0 && counter == 20'd0);

assign mode_sel = mode_sel3;

endmodule
