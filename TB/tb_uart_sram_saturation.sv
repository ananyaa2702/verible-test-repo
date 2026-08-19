`timescale 1ns / 1ps
///////////////////////////////////////////////////////////////////////////////////////////////////
// Module Name: tb_uart_sram_saturation
// Project Name: Silicon SoC
// Description:
// Testbench for (mode_sel = 10) UART -> SRAM loading and
// saturating complete SRAM.
// Dynamically adjusts saturation depth based on the FOR_FPGA macro in
// global_defines.v to test either the Vivado BRAM IP (4096) or the
// SPRAM 8192x36 slice (8192).
//
// NOTE: reset_synch has been removed for post-synthesis compatibility.
// master_resetn drives the system directly.
///////////////////////////////////////////////////////////////////////////////////////////////////

`include "global_defines.v"

module tb_uart_sram_saturation();

	//-------------------------------------//
	// Parameters
	//-------------------------------------//
	localparam integer CLK_FREQ_HZ         = 100_000_000;
	localparam integer UART_LOAD_BAUD      = 1_000_000; // Accelerated baud for simulation
	localparam integer UART_CLKS_PER_BIT   = (CLK_FREQ_HZ / UART_LOAD_BAUD);

	// Dynamically set saturation limit based on global_defines.v
`ifdef FOR_FPGA
	localparam integer TOTAL_WORDS = 4096;
`else
	localparam integer TOTAL_WORDS = 10240;
`endif

	//-------------------------------------//
	// System Signals
	//-------------------------------------//
	reg  clk = 1'b1;
	reg  master_resetn = 1'b0;
	wire resetn;

	//-------------------------------------//
	// DUT Control Signals
	//-------------------------------------//
	reg        load_en  = 1'b0;
	reg  [1:0] mode_sel = 2'b10; // UART Mode
	reg        i_rx_tb  = 1'b1;

	//-------------------------------------//
	// DUT Interfacing Signals
	//-------------------------------------//
	wire       trap;
	wire [9:0] gpio_out;
	wire       load_busy;
	wire       load_done;
	wire       o_rts;
	wire       UART_rx_error;
	wire       UART_check_start;
	wire       header_fail;
	wire       trans_tx;

	wire       CPU_CTS = 1'b0;
	wire       CPU_RTS;
	wire       pcpi_valid;
	wire       pcpi_ready;

	//-------------------------------------//
	// QSPI / Flash Signals
	//-------------------------------------//
	wire       SCK;
	wire       CS_N;
	wire       IO_data_3;
	wire       IO_data_2;
	wire       IO_data_1;
	wire       IO_data_0;
	wire       flash_magic_word;

	//-------------------------------------//
	// Tracking Variables
	//-------------------------------------//
	integer    write_counter = 0;

	//-------------------------------------//
	// Combinational Assignments
	//-------------------------------------//

	// Post-synth safe reset mapping
	assign resetn = master_resetn;

	/*
	 * Clock Generator
	 */
	always #5 clk = ~clk; // 100 MHz clock -> 10ns period

	//-------------------------------------//
	// DUT (System) Instantiation
	//-------------------------------------//
	system uut (
		.clk                        (clk),
		.master_resetn              (master_resetn),
		.trap                       (trap),
		.gpio_out                   (gpio_out),
		.load_en_asynch             (load_en),
		.FW_loader_UART_i_rx        (i_rx_tb),
		.mode_sel_asynch            (mode_sel),
		.load_busy                  (load_busy),
		.load_done                  (load_done),
		.FW_loader_UART_o_rts       (o_rts),
		.FW_loader_UART_rx_error    (UART_rx_error),
		.FW_loader_UART_check_start (UART_check_start),
		.o_qspi_sck                 (SCK),
		.o_qspi_cs_n                (CS_N),
		.qspi_io_3                  (IO_data_3),
		.qspi_io_2                  (IO_data_2),
		.qspi_io_1                  (IO_data_1),
		.qspi_io_0                  (IO_data_0),
		.flash_magic_word           (flash_magic_word),
		.CPU_UART_TRANSCEIVER_TX    (trans_tx),
		.CPU_UART_TRANSCEIVER_RX    (1'b1),
		.CPU_CTS                    (CPU_CTS),
		.CPU_RTS                    (CPU_RTS),
		.pcpi_valid                 (pcpi_valid),
		.pcpi_ready                 (pcpi_ready),
		.FW_loader_UART_header_fail (header_fail)
	);

	//-------------------------------------//
	// Flash Model Instantiation
	//-------------------------------------//
	/*
	 * Flash Memory Dummy to avoid Floating Pins
	 */
	W25Q16JV flash_mem (
		.CSn   (CS_N),
		.CLK   (SCK),
		.DIO   (IO_data_0),
		.DO    (IO_data_1),
		.WPn   (IO_data_2),
		.HOLDn (IO_data_3)
	);

	//-------------------------------------//
	// TB Parameter Overrides
	//-------------------------------------//
	// Align Loader RX timing to our TB properties
	defparam uut.u_sram_ctrl.u_uart_loader_subsystem.u_uart_rx_subsystem.uart_rx_fifo_u.SystemClockFreq = CLK_FREQ_HZ;
	defparam uut.u_sram_ctrl.u_uart_loader_subsystem.u_uart_rx_subsystem.uart_rx_fifo_u.BaudRate = UART_LOAD_BAUD;

	//-------------------------------------//
	// UART TX Bit-Banging Tasks
	//-------------------------------------//

	/*
	 * Wait for single bit duration
	 */
	task automatic uart_wait_bit;
	begin
		repeat (UART_CLKS_PER_BIT) @(posedge clk);
	end
	endtask

	/*
	 * Send one byte via UART with CTS hardware flow control
	 */
	task automatic uart_send_byte_cts;
		input [7:0] b;
		integer i;
	begin
		// Wait for clear-to-send (hardware flow control)
		while (o_rts !== 1'b1) @(posedge clk);

		i_rx_tb = 1'b0; // Start bit
		uart_wait_bit();

		for (i = 0; i < 8; i = i + 1)
		begin
			i_rx_tb = b[i]; // Data bits (LSB first)
			uart_wait_bit();
		end

		i_rx_tb = 1'b1; // Stop bit
		uart_wait_bit();
		uart_wait_bit(); // Extra idle bit to clear cumulative drift
	end
	endtask

	/*
	 * Send a 32-bit word via UART
	 */
	task automatic uart_send_word_cts;
		input [31:0] w;
	begin
		// MSB first for the accumulator
		uart_send_byte_cts(w[31:24]);
		uart_send_byte_cts(w[23:16]);
		uart_send_byte_cts(w[15:8]);
		uart_send_byte_cts(w[7:0]);
	end
	endtask

	//-------------------------------------//
	// Saturation Monitor
	//-------------------------------------//
	/*
	 * Scoreboard logic to track number of words written to SRAM
	 */
	always @(posedge clk)
	begin
		if (!resetn)
		begin
			write_counter <= 0;
		end
		else if (uut.u_sram_wrapper.sram_valid && uut.u_sram_wrapper.sram_wea)
		begin
			write_counter <= write_counter + 1;

			if (write_counter % 1000 == 0 && write_counter > 0)
			begin
				$display("[%0t] Written %0d words to SRAM...", $time, write_counter);
			end

			if (write_counter + 1 == TOTAL_WORDS)
			begin
				$display("=================================================");
				$display("[TB SUCCESS] SRAM SATURATION COMPLETE");
				$display("Target Depth configured: %0d", TOTAL_WORDS);
				$display("Total Words Written: %0d", write_counter + 1);
				$display("Time: %0t", $time);
				$display("=================================================");
				#1000;
				$finish;
			end
		end
	end

	//-------------------------------------//
	// Main Stimulus
	//-------------------------------------//
	initial
	begin
		$display("=================================================");
		$display(" UART to SRAM Saturation Test");
		$display(" Target Words: %0d", TOTAL_WORDS);
		$display("=================================================");

		master_resetn = 1'b0;
		load_en       = 1'b0;
		i_rx_tb       = 1'b1; // Idle high

		// Reset Sequence
		#100;
		master_resetn = 1'b1;
		wait (resetn === 1'b1);
		repeat (20) @(posedge clk);

		// Pulse load_en
		@(posedge clk) load_en = 1'b1;
		repeat (5) @(posedge clk);
		load_en = 1'b0;

		// Start Sending Header (0xA5D5 + Total Words)
		$display("[%0t] Sending Firmware Header...", $time);
		uart_send_word_cts({16'hA5D5, TOTAL_WORDS[15:0]});

		// Start Saturating SRAM
		$display("[%0t] Saturating SRAM with %0d words...", $time, TOTAL_WORDS);
		for (int i = 0; i < TOTAL_WORDS; i++)
		begin
			uart_send_word_cts(i); // Fill sequentially
		end

		// Wait for completion (Watchdog)
		repeat (1_000_000) @(posedge clk);
		$display("[TB ERROR] Simulation Timed Out. Words Written: %0d / %0d", write_counter, TOTAL_WORDS);
		$finish;
	end

endmodule