`timescale 1ns / 1ps
///////////////////////////////////////////////////////////////////////////////////////////////////
// Engineer: Rakesh Patil, Shashank Tiwari, Samyak Nidhi
// Update Date: 04.07.2026
// Module Name: tb_reset_synch.sv
// Project Name: Silicon SoC kNN
// Description:
// Independent testbench for verifying reset_synch.v functionality in the design. Need to use
// post synthesis vivado timing simulation for accurate results. Decimal # delay values are used
// to simulate applying an asynchronous master reset signal to the synchroniser.
///////////////////////////////////////////////////////////////////////////////////////////////////

module tb_reset_synch();

	localparam integer FF_COUNT = 5;

	reg  clk;
	reg  master_resetn;
	wire resetn;

reset_synch #(
	.FF_COUNT(FF_COUNT)
) uut (
	.clk(clk),
	.master_resetn(master_resetn),
	.resetn(resetn)
);

	integer pass_count = 0;
	integer cycle_count;
	integer success;

	initial
	begin
		clk = 1'b0;
		forever #5 clk = ~clk; // 100 MHz clock
	end

	task apply_async_master_resetn(input val, input real delay_val);
	begin
		#delay_val;
		master_resetn = val;
	end
	endtask

	initial
	begin
		// Initialize to active reset
		master_resetn = 1'b0;
		#100;

		// --------------------------------------------------------
		// Test 1: Synchronous Deassertion (Release from reset)
		// --------------------------------------------------------
		// Release the reset asynchronously in the middle of a clock cycle
		@(posedge clk);
		apply_async_master_resetn(1'b1, 2.15);

		cycle_count = 0;
		success = 0;

		while (cycle_count < (FF_COUNT + 3) && !success)
		begin
			@(posedge clk);
			cycle_count = cycle_count + 1;

			if (resetn === 1'b1)
				success = 1;
		end

		if (success == 0)
			$display("Test FAILED: resetn did not synchronise to 1");
		else if (cycle_count < FF_COUNT)
			$display("Test FAILED: resetn synchronised too early (took %0d cycles, expected >= %0d)", cycle_count, FF_COUNT);
		else
		begin
			$display("Test PASSED: resetn synchronised to 1 after %0d cycles", cycle_count);
			pass_count = pass_count + 1;
		end

		#1000;

		// --------------------------------------------------------
		// Test 2: Asynchronous Assertion (Placing into reset)
		// --------------------------------------------------------
		// Assert active-low reset asynchronously in the middle of a clock cycle
		@(posedge clk);
		apply_async_master_resetn(1'b0, 4.67);

		// For an asynchronous reset, the output should fall immediately
		// (plus a tiny delta for gate delay in post-synth)
		#10;
		if (resetn !== 1'b0)
			$display("Test FAILED: resetn did not assert asynchronously");
		else
		begin
			$display("Test PASSED: resetn asserted asynchronously");
			pass_count = pass_count + 1;
		end

		#1000;

		if(pass_count == 2)
			$display("All tests PASSED");
		else
			$display("%d tests PASSED, %d tests FAILED", pass_count, 2-pass_count);

		$finish;
	end

endmodule