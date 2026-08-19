`timescale 1ns / 1ps
///////////////////////////////////////////////////////////////////////////////////////////////////
// Engineer: Shashank Tiwari, Samyak Nidhi
// Update Date: 04.04.2026
// Module Name: tb_uart_rx_subsystem
// Project Name: Silicon SoC rev 1.0
// Description:
// Testbench for verifying UART RX functioning after receiving words (from byte acc).
// Test order:
// Sending words via UART and verifying they correctly appear on the 32-bit output 
// bus when requested. Fixed to use the 100MHz clock expected by the hardware.
///////////////////////////////////////////////////////////////////////////////////////////////////

module tb_uart_rx_subsystem;

	//-------------------------------------//
	// Parameters
	//-------------------------------------//
	localparam int CLK_FREQ = 100_000_000; // FIXED: Must match underlying UART RTL hardware
	localparam int BAUD     = 115200;
	localparam int BIT_TIME = 1_000_000_000 / BAUD; // ~8680 ns

	//-------------------------------------//
	// System Signals
	//-------------------------------------//
	logic i_clk;
	logic i_rst_n;

	//-------------------------------------//
	// DUT I/O
	//-------------------------------------//
	logic        i_rx;
	logic        UART_rd_en;
	logic [31:0] o_word_data;
	logic        o_rts;
	logic        word_read_done;

	//-------------------------------------//
	// Scoreboard
	//-------------------------------------//
	integer pass_count = 0;
	integer fail_count = 0;

	//-------------------------------------//
	// DUT Instantiation
	//-------------------------------------//
	uart_rx_subsystem dut (
		.i_clk          (i_clk),
		.i_rst_n        (i_rst_n),
		.i_rx           (i_rx),
		.UART_rd_en     (UART_rd_en),
		.o_word_data    (o_word_data),
		.o_rts          (o_rts),
		.word_read_done (word_read_done)
	);

	//-------------------------------------//
	// Clock Generation (100 MHz)
	//-------------------------------------//
	initial 
	begin
		i_clk = 0;
		forever #5 i_clk = ~i_clk; // FIXED: 10ns period -> 100MHz
	end

	//-------------------------------------//
	// Helper Tasks
	//-------------------------------------//
	task automatic send_byte(input logic [7:0] b);
	begin
		i_rx = 1'b0; #(BIT_TIME); // START bit
		for (int i = 0; i < 8; i++) 
		begin
			i_rx = b[i]; #(BIT_TIME); // DATA bits (LSB first)
		end
		i_rx = 1'b1; #(BIT_TIME); // STOP bit
	end
	endtask

	task automatic send_word(input logic [7:0] b3, input logic [7:0] b2, input logic [7:0] b1, input logic [7:0] b0);
	begin
		// Assuming MSB first based on your original test sequence
		send_byte(b3);
		send_byte(b2);
		send_byte(b1);
		send_byte(b0);
	end
	endtask

	task automatic request_word();
	begin
		@(posedge i_clk);
		UART_rd_en = 1'b1;
		@(posedge i_clk);
		UART_rd_en = 1'b0;
	end
	endtask

	task automatic wait_for_word();
	begin
		automatic int timeout = 0;
		while (!word_read_done && timeout < 100_000) 
		begin
			@(posedge i_clk);
			timeout++;
		end
		if (timeout >= 100_000) 
		begin
			$display("[%0t] ERROR: Timeout waiting for word_read_done", $time);
		end
	end
	endtask

	task automatic check_result(input string test_name, input logic [31:0] expected);
	begin
		if (o_word_data !== expected) 
		begin
			$display("[FAIL] %s: Expected 0x%08h, got 0x%08h", test_name, expected, o_word_data);
			fail_count++;
		end 
		else 
		begin
			$display("[PASS] %s: Successfully received 0x%08h", test_name, o_word_data);
			pass_count++;
		end
	end
	endtask

	//-------------------------------------//
	// Main Test Sequence
	//-------------------------------------//
	initial 
	begin
		// Initialize
		i_rst_n    = 0;
		i_rx       = 1'b1; // UART idle
		UART_rd_en = 0;

		$display("================================================================");
		$display(" TB: uart_rx_subsystem");
		$display("================================================================");

		repeat (10) @(posedge i_clk);
		i_rst_n = 1;
		repeat (10) @(posedge i_clk);

		// ============================================================
		// TEST 1
		// ============================================================
		$display("\n--- TEST 1: Sending 11 22 33 44 ---");
		send_word(8'h11, 8'h22, 8'h33, 8'h44);
		request_word();
		wait_for_word();
		check_result("TEST 1", 32'h11_22_33_44);

		// ============================================================
		// TEST 2
		// ============================================================
		$display("\n--- TEST 2: Sending AA BB CC DD ---");
		send_word(8'hAA, 8'hBB, 8'hCC, 8'hDD);
		request_word();
		wait_for_word();
		check_result("TEST 2", 32'hAA_BB_CC_DD);

		// ============================================================
		// TEST 3 (Added for robustness)
		// ============================================================
		$display("\n--- TEST 3: Sending 55 66 77 88 ---");
		send_word(8'h55, 8'h66, 8'h77, 8'h88);
		request_word();
		wait_for_word();
		check_result("TEST 3", 32'h55_66_77_88);

		// ============================================================
		// SUMMARY
		// ============================================================
		$display("\n================================================================");
		$display(" RESULTS: %0d PASSED, %0d FAILED (total %0d)",
			pass_count, fail_count, pass_count + fail_count);

		if (fail_count == 0)
			$display(" ??? ALL TESTS PASSED ???");
		else
			$display(" ??? %0d TEST(S) FAILED ???", fail_count);
		$display("================================================================");

		#1000;
		$finish;
	end

	//-------------------------------------//
	// Global timeout watchdog
	//-------------------------------------//
	initial 
	begin
		#(100_000_000); // 100 ms timeout
		$display("[TIMEOUT] Simulation exceeded 100ms limit");
		$finish;
	end

endmodule