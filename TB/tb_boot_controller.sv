`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Tanish A Shet, Shashank Tiwari, Samyak Nidhi
// Module Name: tb_boot_controller
// Project: Silicon SoC rev 1.0
// Description: Comprehensive testbench for boot_controller module.
// 1) Check of boot mode, FIFO and UART mode is done where load enable is pulsed, wait till
// boot_en is high then after 100 cycles of this we manually assert boot_load_done and check
// whether resetn_core_req was enabled by core or not, if so then test passes
// 2) On illegal mode select state of fsm should be stuck indefinately in SAMPLE state
// this is the second test.
// 3) Async Reset assertion, when this happens in middle of loading then we check whether
// resetn_core_req, fw_load_en, boot_en are all cleared
// 4) Load enable held high (with our latest rtl this test should fail)
// 5) State Transition coverage: check if each state is actually encountered or not.
// Throughout: Monitor display of main signals as discussed above.
//////////////////////////////////////////////////////////////////////////////////

module tb_boot_controller();

	// Testbench signals
	logic clk;
	logic load_en;
	logic resetn_in;
	logic UART_load_done;
	logic FIFO_load_done;
	logic boot_load_done;
	logic [2:0] mode_sel;

	logic resetn_core_req;
	logic boot_en;
	logic fw_load_en;

	// Instantiate the Unit Under Test (UUT)
	boot_controller uut (
		.clk(clk),
		.load_en(load_en),
		.resetn_in(resetn_in),
		.UART_load_done(UART_load_done),
		.FIFO_load_done(FIFO_load_done),
		.boot_load_done(boot_load_done),
		.mode_sel(mode_sel),
		.resetn_core_req(resetn_core_req),
		.boot_en(boot_en),
		.fw_load_en(fw_load_en)
	);

	// Clock generation - 10ns period (100MHz)
	initial begin
		clk = 0;
		forever #5 clk = ~clk;
	end

	// Test stimulus
	initial begin
		// Initialize waveform dump
		$dumpfile("boot_controller_tb.vcd");
		$dumpvars(0, tb_boot_controller);

		// Initialize all inputs
		load_en = 0;
		resetn_in = 0;
		UART_load_done = 0;
		FIFO_load_done = 0;
		boot_load_done = 0;
		mode_sel = 2'b00;

		// Display header
		$display("\n========================================");
		$display("Boot Controller Testbench Started");
		$display("========================================\n");

		// Apply reset
		$display("[%0t] Applying reset...", $time);
		#20;
		resetn_in = 1;
		#10;
		$display("[%0t] Reset released\n", $time);

		//==============================================
		// TEST CASE 1: Boot Mode (mode_sel = 2'b00)
		//==============================================
		$display("========================================");
		$display("TEST CASE 1: Boot Mode (Direct Reset Release)");
		$display("========================================");
		mode_sel = 2'b00;
		#10;

		$display("[%0t] Asserting load_en", $time);
		load_en = 1;
		#10;
		load_en = 0;

		// Wait for boot_en to assert
		wait(boot_en == 1);
		$display("[%0t] boot_en asserted", $time);

		// Simulate boot completion after some cycles
		#100;
		$display("[%0t] Asserting boot_load_done", $time);
		boot_load_done = 1;
		#10;

		// Check if resetn_core_req is asserted
		if(resetn_core_req)
			$display("[%0t] PASS: resetn_core_req asserted", $time);
		else
			$display("[%0t] FAIL: resetn_core_req not asserted", $time);

		#20;
		boot_load_done = 0; // Clear done signal
		#50;

		//==============================================
		// TEST CASE 2: FIFO Load Mode (mode_sel = 2'b01)
		//==============================================
		$display("\n========================================");
		$display("TEST CASE 2: FIFO Load Mode");
		$display("========================================");
		mode_sel = 2'b01;
		#10;

		$display("[%0t] Asserting load_en", $time);
		load_en = 1;
		#10;
		load_en = 0;

		// Wait for fw_load_en to assert
		wait(fw_load_en == 1);
		$display("[%0t] fw_load_en asserted", $time);

		// Simulate FIFO loading for arbitrary cycles
		#150;
		$display("[%0t] Asserting FiFO_load_done", $time);
		FIFO_load_done = 1;
		#30;

		// Check if resetn_core_req is asserted
		if(resetn_core_req)
			$display("[%0t] PASS: resetn_core_req asserted after FIFO load", $time);
		else
			$display("[%0t] FAIL: resetn_core_req not asserted", $time);

		#20;
		FIFO_load_done = 0; // Clear done signal
		#50;

		//==============================================
		// TEST CASE 3: UART Load Mode (mode_sel = 2'b10)
		//==============================================
		$display("\n========================================");
		$display("TEST CASE 3: UART Load Mode");
		$display("========================================");
		mode_sel = 2'b10;
		#10;

		$display("[%0t] Asserting load_en", $time);
		load_en = 1;
		#10;
		load_en = 0;

		// Wait for fw_load_en to assert
		wait(fw_load_en == 1);
		$display("[%0t] fw_load_en asserted", $time);

		// Simulate UART loading for arbitrary cycles
		#200;
		$display("[%0t] Asserting UART_load_done", $time);
		UART_load_done = 1;
		#30;

		// Check if resetn_core_req is asserted
		if(resetn_core_req)
			$display("[%0t] PASS: resetn_core_req asserted after UART load", $time);
		else
			$display("[%0t] FAIL: resetn_core_req not asserted", $time);

		#20;
		UART_load_done = 0; // Clear done signal
		#50;

		//==============================================
		// TEST CASE 4: Invalid Mode (mode_sel = 2'b11)
		//==============================================
		$display("\n========================================");
		$display("TEST CASE 4: Invalid Mode Selection");
		$display("========================================");
		mode_sel = 2'b11;
		#10;

		$display("[%0t] Asserting load_en with mode_sel = 2'b11", $time);
		load_en = 1;
		#10;
		load_en = 0;

		#50;
		// Check that system stays in SAMPLE state (no boot_en or fw_load transitions)
		if(uut.state == uut.SAMPLE)
			$display("[%0t] PASS: System correctly stays in SAMPLE state", $time);
		else
			$display("[%0t] FAIL: System transitioned from SAMPLE state", $time);

		// Reset to get out of this state
		resetn_in = 0;
		#20;
		resetn_in = 1;
		#20;

		//==============================================
		// TEST CASE 5: Asynchronous Reset During Operation
		//==============================================
		$display("\n========================================");
		$display("TEST CASE 5: Asynchronous Reset Test");
		$display("========================================");
		mode_sel = 2'b01;
		#10;

		$display("[%0t] Starting FIFO load operation", $time);
		load_en = 1;
		#10;
		load_en = 0;

		// Wait a bit, then apply reset mid-operation
		#80;
		$display("[%0t] Applying reset during FIFO_LOAD state", $time);
		resetn_in = 0;
		#20;

		// Check that outputs are cleared
		if(resetn_core_req == 0 && fw_load_en == 0 && boot_en == 0)
			$display("[%0t] PASS: All outputs correctly cleared on reset", $time);
		else
			$display("[%0t] FAIL: Outputs not cleared properly", $time);

		resetn_in = 1;
		#50;

		//==============================================
		// TEST CASE 6: Load enable held high
		//==============================================
		$display("\n========================================");
		$display("TEST CASE 6: Load Enable Held High");
		$display("========================================");
		mode_sel = 2'b00;
		#10;

		$display("[%0t] Holding load_en high", $time);
		load_en = 1; // Keep high
		#30;

		// System should still function normally
		if(boot_en == 1)
			$display("[%0t] PASS: System responds with load_en held high", $time);
		else
			$display("[%0t] FAIL: System doesn't respond", $time);

		#100;
		boot_load_done = 1;
		#20;
		boot_load_done = 0;
		load_en = 0;
		#50;

		//==============================================
		// TEST CASE 7: State transition coverage
		//==============================================
		$display("\n========================================");
		$display("TEST CASE 7: Complete State Transition Check");
		$display("========================================");

		// Monitor state transitions
		$display("[%0t] Current State: %0d (IDLE)", $time, uut.state);
		mode_sel = 2'b01;
		load_en = 1;
		#10;
		load_en = 0;
		#10;
		$display("[%0t] Current State: %0d (SAMPLE)", $time, uut.state);
		#10;
		$display("[%0t] Current State: %0d (FIFO_LOAD)", $time, uut.state);
		#100;
		FIFO_load_done = 1;
		#10;
		$display("[%0t] Current State: %0d (RST_RELEASE)", $time, uut.state);
		#10;
		$display("[%0t] Current State: %0d (IDLE)", $time, uut.state);
		FIFO_load_done = 0;
		#50;

		// End simulation
		$display("\n========================================");
		$display("All Test Cases Completed");
		$display("========================================\n");
		#100;
		$finish;
	end

	// Monitor for debugging
	initial begin
		$monitor("[%0t] State=%0d | load_en=%b | mode_sel=%b | fw_load_en=%b | boot_en=%b | resetn_core_req=%b | fw_load_done=%b",
			$time, uut.state, load_en, mode_sel, fw_load_en, boot_en, resetn_core_req, uut.fw_load_done);
	end

	// Timeout watchdog
	initial begin
		#10000;
		$display("\n[ERROR] Simulation timeout!");
		$finish;
	end

endmodule
