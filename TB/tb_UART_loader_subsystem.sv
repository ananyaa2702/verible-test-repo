`timescale 1ns / 1ps
///////////////////////////////////////////////////////////////////////////////////////////////////
// Engineer: Shashank Tiwari, Samyak Nidhi
// Update Date: 04.04.2026
// Module Name: tb_UART_loader_subsystem
// Project Name: Silicon SoC KNN
// Description:
// Simplified testbench for verifying UART firmware loading to SRAM.
// Tests sending a 10-word payload (1 header + 9 data words) and verifies
// the resulting write operations and load_done signaling.
///////////////////////////////////////////////////////////////////////////////////////////////////

module tb_UART_loader_subsystem;

	//---------------------------------//
	// Parameters
	//---------------------------------//
	localparam integer CLK_FREQ = 100_000_000;
	localparam integer BAUD     = 115200;
	localparam integer BIT_TIME = 1_000_000_000 / BAUD; // ~8680 ns
	localparam integer W        = 32;
	localparam integer N        = 13;

	//---------------------------------//
	// System Signals
	//---------------------------------//
	reg clk;
	reg resetn_in;

	//---------------------------------//
	// DUT Interfacing Signals
	//---------------------------------//
	reg          UART_load_en;
	reg          i_rx;
	wire         UART_load_done;
	wire [W-1:0] UART_SRAM_WDATA;
	wire [N-1:0] UART_SRAM_ADDR;
	wire         UART_load_busy;
	wire         o_rts;
	wire         UART_check_start;
	wire         o_rx_error;
	wire         header_fail;
	wire         sram_valid_uart;
	wire         sram_wea_uart;

	//---------------------------------//
	// Tracking Variables
	//---------------------------------//
	integer words_written;
	integer errors;
	integer i;

	reg [31:0] expected_data [0:8];
	reg [N-1:0] expected_addr [0:8];

	//---------------------------------//
	// DUT Instantiation
	//---------------------------------//
	UART_loader_subsystem #(
		.W(W),
		.N(N)
	) dut (
		.clk              (clk),
		.resetn_in        (resetn_in),
		.UART_load_en     (UART_load_en),
		.i_rx             (i_rx),
		.UART_load_done   (UART_load_done),
		.UART_SRAM_WDATA  (UART_SRAM_WDATA),
		.UART_SRAM_ADDR   (UART_SRAM_ADDR),
		.UART_load_busy   (UART_load_busy),
		.o_rts            (o_rts),
		.UART_check_start (UART_check_start),
		.o_rx_error       (o_rx_error),
		.header_fail      (header_fail),
		.sram_valid_uart  (sram_valid_uart),
		.sram_wea_uart    (sram_wea_uart)
	);

	/*
	 * Clock Generation.
	 * Generates a 100 MHz clock to match the UART receiver's
	 * hardcoded hardware parameters.
	 */
	initial
	begin
		clk = 0;
		forever #5 clk = ~clk;
	end

	/*
	 * UART Bit-level Sender Task.
	 * Simulates UART TX sending a START bit, 8 DATA bits (LSB first),
	 * and a STOP bit based on the calculated BIT_TIME.
	 */
	task send_byte;
		input [7:0] b;
		integer bit_idx;
		begin
			// Wait for receiver to be ready (Hardware Flow Control)
			while (o_rts !== 1'b1)
			begin
				@(posedge clk);
			end

			$display("[%0t] TX Byte = 0x%02h", $time, b);

			// START bit
			i_rx = 1'b0;
			#(BIT_TIME);

			// DATA bits (LSB first)
			for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1)
			begin
				i_rx = b[bit_idx];
				#(BIT_TIME);
			end

			// STOP bit
			i_rx = 1'b1;
			#(BIT_TIME);
		end
	endtask

	/*
	 * UART Word Sender Task.
	 * Breaks a 32-bit word into 4 bytes. MSB is sent first to match
	 * the endianness of the byte_acc module inside the hardware.
	 */
	task send_word;
		input [31:0] w;
		begin
			$display("[%0t] ---- TX WORD = 0x%08h ----", $time, w);
			send_byte(w[31:24]); // MSB
			send_byte(w[23:16]);
			send_byte(w[15:8]);
			send_byte(w[7:0]);   // LSB
		end
	endtask

	/*
	 * SRAM Write Monitor.
	 * Monitors the BRAM IP specific write strobes to capture
	 * data and address, then compares it against expected values.
	 */
	always @(posedge clk)
	begin
		if (resetn_in)
		begin
			if (sram_valid_uart && sram_wea_uart)
			begin
				if (words_written < 9)
				begin
					if (UART_SRAM_WDATA !== expected_data[words_written])
					begin
						$display("[%0t] ERROR: SRAM DATA MISMATCH @ addr=0x%03h: expected=0x%08h, got=0x%08h",
							$time, UART_SRAM_ADDR, expected_data[words_written], UART_SRAM_WDATA);
						errors = errors + 1;
					end
					else if (UART_SRAM_ADDR !== expected_addr[words_written])
					begin
						$display("[%0t] ERROR: SRAM ADDR MISMATCH: expected=0x%03h, got=0x%03h",
							$time, expected_addr[words_written], UART_SRAM_ADDR);
						errors = errors + 1;
					end
					else
					begin
						$display("[%0t] MATCH: SRAM[0x%03h] = 0x%08h",
							$time, UART_SRAM_ADDR, UART_SRAM_WDATA);
					end
				end
				else
				begin
					$display("[%0t] ERROR: Unexpected write to SRAM[0x%03h] = 0x%08h",
						$time, UART_SRAM_ADDR, UART_SRAM_WDATA);
					errors = errors + 1;
				end

				words_written = words_written + 1;
			end
		end
	end

	/*
	 * Main Test Sequence.
	 */
	initial
	begin
		// Initialize signals
		i_rx         = 1'b1;
		resetn_in    = 0;
		UART_load_en = 0;
		errors       = 0;
		words_written = 0;

		// Initialize expected data arrays
		expected_data[0] = 32'h11111111; expected_addr[0] = 13'h0000;
		expected_data[1] = 32'h22222222; expected_addr[1] = 13'h0001;
		expected_data[2] = 32'h33333333; expected_addr[2] = 13'h0002;
		expected_data[3] = 32'h44444444; expected_addr[3] = 13'h0003;
		expected_data[4] = 32'h55555555; expected_addr[4] = 13'h0004;
		expected_data[5] = 32'h66666666; expected_addr[5] = 13'h0005;
		expected_data[6] = 32'h77777777; expected_addr[6] = 13'h0006;
		expected_data[7] = 32'h88888888; expected_addr[7] = 13'h0007;
		expected_data[8] = 32'h99999999; expected_addr[8] = 13'h0008;

		// Reset sequence
		repeat (10) @(posedge clk);
		resetn_in = 1;
		repeat (10) @(posedge clk);

		$display("\n========================================================");
		$display("TEST: 10-word firmware load (Header + 9 data words)");
		$display("========================================================\n");

		// Step 1: Trigger UART loader
		$display("[%0t] Step 1: Asserting UART_load_en", $time);
		@(posedge clk);
		UART_load_en = 1;
		@(posedge clk);
		UART_load_en = 0;

		repeat (20) @(posedge clk);

		// Step 2: Send HEADER word
		$display("\n[%0t] Step 2: Sending HEADER word (0xA5D5_0009)", $time);
		send_word(32'hA5D5_0009);

		repeat (100) @(posedge clk);

		// Step 3: Send 9 data words
		$display("\n[%0t] Step 3: Sending 9 data words", $time);
		for (i = 0; i < 9; i = i + 1)
		begin
			send_word(expected_data[i]);
			repeat (10) @(posedge clk);
		end

		// Step 4: Wait for completion
		$display("\n[%0t] Step 4: Waiting for UART_load_done...", $time);

		fork
			begin : wait_done
				while (!UART_load_done)
				begin
					@(posedge clk);
				end
				$display("[%0t] UART_load_done asserted!", $time);
			end
			begin : timeout
				#50_000_000; // 50 ms timeout
				$display("[%0t] ERROR: TIMEOUT waiting for UART_load_done", $time);
				errors = errors + 1;
			end
		join_any
		disable wait_done;
		disable timeout;

		// Step 5: Verify results
		$display("\n[%0t] Step 5: Verifying results...", $time);

		if (words_written != 9)
		begin
			$display("[%0t] ERROR: Expected 9 words written, got %0d", $time, words_written);
			errors = errors + 1;
		end
		else
		begin
			$display("[%0t] MATCH: Correct number of words written: %0d", $time, words_written);
		end

		if (header_fail)
		begin
			$display("[%0t] ERROR: Header check failed unexpectedly", $time);
			errors = errors + 1;
		end
		else
		begin
			$display("[%0t] MATCH: Header check passed", $time);
		end

		// Final Report
		$display("\n========================================");
		if (errors == 0)
			$display("??? ALL TESTS PASSED ???");
		else
			$display("??? %0d ERROR(S) DETECTED ???", errors);
		$display("========================================\n");

		repeat (10) @(posedge clk);
		$finish;
	end

endmodule