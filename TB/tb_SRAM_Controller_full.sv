`timescale 1ns / 1ps
///////////////////////////////////////////////////////////////////////////////////////////////////
// Engineer: Shashank Tiwari, Samyak Nidhi
// Update Date: 27.03.2026
// Module Name: tb_SRAM_Controller_full (Custom RTL)
// Project Name: Silicon SoC rev 1.0
// Description:
// Testbench for verifying addr_decoder integration within SRAM_controller.
// Test order:
// 1. Reset check: Verify controller outputs stay low and address floats when decoder is disabled.
// 2. UART load test: Send correct header (0xA5D5) and 10 words. Verify SRAM gets UART data, not core data.
// 3. Bad header test: Send incorrect header, verify header_fail flag activates.
// 4. Idle check: Verify all control signals return low after UART loading completes.
// 5. Core write test: Walk through memory addresses. Verify SRAM data and address match core inputs.
// 6. Watchdog & Stats: 500ms safety timeout to prevent hangs. Prints final pass/fail results.
// Continuous monitoring via SystemVerilog assertions ensures correct behavior throughout all tests.
///////////////////////////////////////////////////////////////////////////////////////////////////

module tb_SRAM_Controller_full;

	//-------------------------------------//
	// Parameters
	//-------------------------------------//
	localparam int CLK_FREQ       = 100_000_000; // FIXED: Must match UART RTL hardware
	localparam int BAUD           = 115200;
	localparam int BIT_TIME       = 1_000_000_000 / BAUD; // ~8680 ns
	localparam int W              = 32;
	localparam int N              = 13;

	//-------------------------------------//
	// DUT I/O
	//-------------------------------------//
	logic           clk;
	logic           resetn_in;
	logic           load_en;
	logic           i_rx;
	logic [1:0]     mode_sel;
	logic [W-1:0]   CORE_WDATA;
	logic [31:0]    CORE_ADDR;
	logic           core_decoder_en;
	logic           core_decoder_en_remap = 1'b0;
	logic           load_busy_core        = 1'b0;
	logic           load_done_core        = 1'b0;

	//-------------------------------------//
	// Outputs
	//-------------------------------------//
	logic           sync_core_resetn;
	logic           fw_load_en;
	logic [W-1:0]   SRAM_WDATA;
	logic [31:0]    SRAM_ADDR_RAW;
	logic [N-1:0]   decoded_SRAM_ADDR;
	logic           load_busy;
	logic           load_done;
	logic           o_rts;
	logic           UART_check_start;
	logic           UART_rx_error;
	logic           boot_en;
	logic           header_fail;
	logic           sram_valid_uart;
	logic           sram_wea_uart;

	//-------------------------------------//
	// Scoreboard
	//-------------------------------------//
	integer pass_count = 0;
	integer fail_count = 0;

	//-------------------------------------//
	// VCD Debug Signals
	//-------------------------------------//
	logic [31:0] tb_current_header_sent = 32'd0;

	//-------------------------------------//
	// DUT Instantiation
	//-------------------------------------//
	SRAM_controller #(
		.N(N),
		.W(W)
	) dut (
		.clk              (clk),
		.resetn_in        (resetn_in),
		.load_en          (load_en),
		.i_rx             (i_rx),
		.mode_sel         (mode_sel),
		.load_busy_core   (load_busy_core),
		.load_done_core   (load_done_core),
		.CORE_WDATA       (CORE_WDATA),
		.CORE_ADDR        (CORE_ADDR),
		.sync_core_resetn (sync_core_resetn),
		.boot_en          (boot_en),
		.SRAM_ADDR_RAW    (SRAM_ADDR_RAW),
		.fw_load_en       (fw_load_en),
		.SRAM_WDATA       (SRAM_WDATA),
		.load_busy        (load_busy),
		.load_done        (load_done),
		.o_rts            (o_rts),
		.UART_check_start (UART_check_start),
		.UART_rx_error    (UART_rx_error),
		.header_fail      (header_fail),
		.sram_valid_uart  (sram_valid_uart),
		.sram_wea_uart    (sram_wea_uart)
	);

	addr_decoder #(
		.N(N)
	) u_addr_decoder (
		.fw_load_en           (fw_load_en),
		.core_decoder_en      (core_decoder_en),
		.core_decoder_en_remap(core_decoder_en_remap),
		.mode_sel             (mode_sel),
		.SRAM_ADDR_RAW        (SRAM_ADDR_RAW),
		.SRAM_ADDR            (decoded_SRAM_ADDR)
	);

	//-------------------------------------//
	// Clock generation: 100 MHz
	//-------------------------------------//
	initial clk = 0;
	always #5 clk = ~clk; // FIXED: 10ns period -> 100MHz

	//-------------------------------------//
	// Helper tasks
	//-------------------------------------//
	task automatic wait_cycles(input int c);
	begin
		for (int i = 0; i < c; i++) @(posedge clk);
	end
	endtask

	task automatic master_reset();
	begin
		resetn_in       = 1'b0;
		load_en         = 1'b0;
		i_rx            = 1'b1; // idle
		mode_sel        = 2'b10; // UART mode
		CORE_WDATA      = {W{1'b0}};
		CORE_ADDR       = 32'd0;
		core_decoder_en = 1'b0;
		core_decoder_en_remap = 1'b0;
		load_busy_core  = 1'b0;
		load_done_core  = 1'b0;
		wait_cycles(10);
		resetn_in = 1'b1;
		wait_cycles(10);
	end
	endtask

	//-------------------------------------//
	// UART byte sender (for loading firmware to trigger fw_load_en)
	//-------------------------------------//
	task automatic send_byte_raw(input logic [7:0] b);
	begin
		i_rx = 1'b0; #(BIT_TIME); // START
		for (int i = 0; i < 8; i++) begin
			i_rx = b[i]; #(BIT_TIME); // DATA LSB first
		end
		i_rx = 1'b1; #(BIT_TIME); // STOP
	end
	endtask

	task automatic send_word_raw(input logic [31:0] w);
	begin
		send_byte_raw(w[31:24]);
		send_byte_raw(w[23:16]);
		send_byte_raw(w[15:8]);
		send_byte_raw(w[7:0]);
	end
	endtask

	task automatic wait_rts_high(input int max_cycles);
	int c;
	begin
		c = 0;
		while (o_rts !== 1'b1) begin
			@(posedge clk);
			c++;
			if (c >= max_cycles) begin
				$display("[%0t] Timeout waiting for o_rts=1", $time);
				return;
			end
		end
	end
	endtask

	task automatic send_byte_cts(input logic [7:0] b);
	begin
		wait_rts_high(400_000);
		send_byte_raw(b);
	end
	endtask

	task automatic send_word_cts(input logic [31:0] w);
	begin
		send_byte_cts(w[31:24]);
		send_byte_cts(w[23:16]);
		send_byte_cts(w[15:8]);
		send_byte_cts(w[7:0]);
	end
	endtask

	//-------------------------------------//
	// Address decoder check task
	//-------------------------------------//
	task automatic check_addr;
	input [N-1:0] expected;
	input string test_name;
	begin
		@(posedge clk);
		#1;
		if (decoded_SRAM_ADDR === expected) begin
			$display("[PASS] %0s | CORE_ADDR=0x%04h fw_load_en=%b core_dec_en=%b => decoded=0x%04h (exp 0x%04h)",
				 test_name, CORE_ADDR, fw_load_en, core_decoder_en,
				 decoded_SRAM_ADDR, expected);
			pass_count = pass_count + 1;
		end else begin
			$display("[FAIL] %0s | CORE_ADDR=0x%04h fw_load_en=%b core_dec_en=%b => decoded=0x%04h (exp 0x%04h)",
				 test_name, CORE_ADDR, fw_load_en, core_decoder_en,
				 decoded_SRAM_ADDR, expected);
			fail_count = fail_count + 1;
		end
	end
	endtask

	//-------------------------------------//
	// Check SRAM_WDATA passthrough when fw_load_en=0
	//-------------------------------------//
	task automatic check_wdata_passthrough;
	input [W-1:0] expected;
	input string test_name;
	begin
		@(posedge clk);
		#1;
		if (SRAM_WDATA === expected) begin
			$display("[PASS] %0s | SRAM_WDATA=0x%08h (exp 0x%08h)", test_name, SRAM_WDATA, expected);
			pass_count = pass_count + 1;
		end else begin
			$display("[FAIL] %0s | SRAM_WDATA=0x%08h (exp 0x%08h)", test_name, SRAM_WDATA, expected);
			fail_count = fail_count + 1;
		end
	end
	endtask

	//-------------------------------------//
	// Loader inactivity check when fw_load_en=0
	//-------------------------------------//
	task automatic check_loaders_inactive;
	input string test_name;
	integer local_fail;
	begin
		@(posedge clk);
		#1;
		local_fail = 0;

		if (fw_load_en !== 1'b0) begin
			$display("[FAIL] %0s | fw_load_en should be 0, got %b", test_name, fw_load_en);
			local_fail = 1;
		end

		if (boot_en !== 1'b0) begin
			$display("[FAIL] %0s | boot_en should be 0, got %b", test_name, boot_en);
			local_fail = 1;
		end

		if (load_busy !== 1'b0) begin
			$display("[FAIL] %0s | load_busy should be 0, got %b", test_name, load_busy);
			local_fail = 1;
		end

		if (local_fail) begin
			fail_count = fail_count + 1;
		end else begin
			$display("[PASS] %0s | All loader outputs inactive as expected", test_name);
			pass_count = pass_count + 1;
		end
	end
	endtask

	//-------------------------------------//
	// Loader activity check when fw_load_en=1
	//-------------------------------------//
	task automatic check_loaders_active;
	input string test_name;
	begin
		@(posedge clk);
		#1;
		if (fw_load_en !== 1'b1) begin
			$display("[FAIL] %0s | fw_load_en should be 1, got %b", test_name, fw_load_en);
			fail_count = fail_count + 1;
		end else begin
			$display("[PASS] %0s | fw_load_en=1 (loaders active)", test_name);
			pass_count = pass_count + 1;
		end
	end
	endtask

	//-------------------------------------//
	// Header fail flag checker
	//-------------------------------------//
	task automatic check_header_fail_flag;
	input string test_name;
	begin
		bit saw_fail;
		saw_fail = 0;
		repeat (5000) begin
			@(posedge clk);
			if (header_fail === 1'b1) begin
				saw_fail = 1;
			end
		end
		if (saw_fail) begin
			$display("[PASS] %0s | header_fail asserted as expected", test_name);
			pass_count = pass_count + 1;
		end else begin
			$display("[FAIL] %0s | header_fail never asserted", test_name);
			fail_count = fail_count + 1;
		end
	end
	endtask

	task automatic clear_header_fail_after_delay;
	begin
		repeat (2000) @(posedge clk);
	end
	endtask

	//-------------------------------------//
	// Ensure CORE_WDATA blocked while fw_load_en=1
	//-------------------------------------//
	task automatic check_core_wdata_blocked;
	input [W-1:0] core_data;
	input string test_name;
	begin
		#1;
		if (SRAM_WDATA === core_data) begin
			$display("[FAIL] %0s | SRAM_WDATA=0x%08h equals CORE_WDATA during UART load (should be blocked)",
				 test_name, SRAM_WDATA);
			fail_count = fail_count + 1;
		end else begin
			$display("[PASS] %0s | SRAM_WDATA=0x%08h != CORE_WDATA=0x%08h (correctly blocked)",
				 test_name, SRAM_WDATA, core_data);
			pass_count = pass_count + 1;
		end
	end
	endtask

	//-------------------------------------//
	// Continuous assertions (SystemVerilog concurrent assertions)
	// These fire throughout the simulation
	//-------------------------------------//

	// ASSERTION 1: When fw_load_en=0 and core_decoder_en=1, decoder outputs the word-aligned CORE address
	property p_decode_when_core_active;
		@(posedge clk) disable iff (!resetn_in)
		(!fw_load_en && core_decoder_en) |-> (decoded_SRAM_ADDR == CORE_ADDR[N+1:2]);
	endproperty
	assert property (p_decode_when_core_active)
	else $error("[ASSERT FAIL] decoded_SRAM_ADDR != CORE_ADDR word address when fw_load_en=0 and core_decoder_en=1");

	// ASSERTION 2: When fw_load_en=0 and core_decoder_en=0, outputs should be high-Z (tri-state)
	property p_tristate_when_both_disabled;
		@(posedge clk) disable iff (!resetn_in)
		(!fw_load_en && !core_decoder_en) |-> (decoded_SRAM_ADDR === 13'bz); // FIXED Z Count
	endproperty
	assert property (p_tristate_when_both_disabled)
	else $error("[ASSERT FAIL] decoded_SRAM_ADDR not high-Z when fw_load_en=0 and core_decoder_en=0");

	// ASSERTION 3: When fw_load_en=1, SRAM_WDATA must come from FW path (not CORE)
	//   We check SRAM_WDATA != CORE_WDATA only when CORE_WDATA != 0 (to avoid false positives)
	property p_wdata_from_fw_during_load;
		@(posedge clk) disable iff (!resetn_in)
		(fw_load_en && (CORE_WDATA != 0)) |-> (SRAM_WDATA != CORE_WDATA);
	endproperty
	assert property (p_wdata_from_fw_during_load)
	else $error("[ASSERT FAIL] SRAM_WDATA == CORE_WDATA during fw_load_en=1 (UART writing, CORE should be blocked)");

	// ASSERTION 4: When fw_load_en=0 and core_decoder_en=1, SRAM_WDATA must equal CORE_WDATA
	property p_wdata_from_core_when_active;
		@(posedge clk) disable iff (!resetn_in)
		(!fw_load_en && core_decoder_en) |-> (SRAM_WDATA == CORE_WDATA);
	endproperty
	assert property (p_wdata_from_core_when_active)
	else $error("[ASSERT FAIL] SRAM_WDATA != CORE_WDATA when fw_load_en=0 and core_decoder_en=1");

	// ASSERTION 5: When fw_load_en=0, SRAM_WDATA must mirror CORE_WDATA regardless of decoder enables
	property p_wdata_from_core_when_fw_off;
		@(posedge clk) disable iff (!resetn_in)
		(!fw_load_en) |-> (SRAM_WDATA == CORE_WDATA);
	endproperty
	assert property (p_wdata_from_core_when_fw_off)
	else $error("[ASSERT FAIL] SRAM_WDATA != CORE_WDATA when fw_load_en=0");

	// ASSERTION 6: After reset, fw_load_en must be 0
	property p_fw_load_en_after_reset;
		@(posedge clk)
		($fell(resetn_in)) |=> (fw_load_en == 1'b0);
	endproperty
	assert property (p_fw_load_en_after_reset)
	else $error("[ASSERT FAIL] fw_load_en not 0 after reset");

	// ASSERTION 7: When fw_load_en=0, boot_en must be 0
	property p_boot_en_inactive;
		@(posedge clk) disable iff (!resetn_in)
		(!fw_load_en) |-> (boot_en == 1'b0);
	endproperty
	assert property (p_boot_en_inactive)
	else $error("[ASSERT FAIL] boot_en active when fw_load_en=0");

	//-------------------------------------//
	// Main Test Sequence
	//-------------------------------------//
	initial begin
//	$dumpfile("tb_SRAM_Controller_full.vcd");
//	$dumpvars(0, tb_SRAM_Controller_full);

	$display("================================================================");
	$display(" Integration TB: SRAM_controller + addr_decoder");
	$display(" CORE word address = CORE_ADDR[N+1:2] when decoder active");
	$display("================================================================");

	// ==============================================================
	// PHASE 0: Reset and initial state checks
	// ==============================================================
	$display("\n--- PHASE 0: Reset & Initial State ---");
	master_reset();

	check_loaders_inactive("Post-reset: loaders inactive");

	// After reset with core_decoder_en=0, outputs should be high-Z
	CORE_ADDR = 13'h0000;
	check_addr(13'bz, "Post-reset: CORE_ADDR=0, decode off => high-Z"); // FIXED Z count

	CORE_ADDR = 13'h0900;
	check_addr(13'bz, "Post-reset: CORE_ADDR=0x900, decode off => high-Z"); // FIXED Z count

	// ==============================================================
	// PHASE 1: UART LOAD TEST - Send 10 words via UART
	//   During UART load, CORE_WDATA should NOT appear on SRAM_WDATA
	//   Decoder should be driven by UART path, not CORE path
	// ==============================================================
	$display("\n--- PHASE 1: UART Load Test (10 words) ---");
	$display("  Setting CORE_WDATA=0x99999999 and CORE_ADDR=0x999 during UART load");
	$display("  Asserting that CORE_WDATA does NOT leak to SRAM_WDATA during load");

	master_reset();

	// Set CORE side values that should be BLOCKED during UART load
	CORE_WDATA      = 32'h9999_9999;
	// This should NOT appear on SRAM_WDATA during load
	CORE_ADDR       = 13'h0999;
	// Changed from 0x800 to 0x999
	core_decoder_en = 1'b0;

	// Enable UART load mode
	mode_sel = 2'b10;
	load_en  = 1'b1;
	wait_cycles(5);

	// Wait for fw_load_en to assert
	begin
		automatic int timeout = 0;
		while (fw_load_en !== 1'b1 && timeout < 100) begin
			@(posedge clk);
			timeout++;
		end
	end

	check_loaders_active("UART load: fw_load_en asserted");

	// Send header: 0xA5D5 + 10 words
	$display("  Sending UART header + 10 data words...");
	begin
		logic [31:0] header;
		header = {16'hA5D5, 16'd10}; // 10 data words
		tb_current_header_sent = header;
		send_word_cts(header);

		// Send 10 data words and check assertion after each word
		for (int word_idx = 0; word_idx < 10; word_idx++) begin
			logic [31:0] data_word;
			data_word = 32'h1000_0000 * (word_idx + 1); // 0x10000000, 0x20000000, etc.

			$display("  Sending word %0d: 0x%08h", word_idx, data_word);
			send_word_cts(data_word);

			// Keep CORE_WDATA constant at 0x99999999 during entire UART load
			CORE_WDATA = 32'h9999_9999;
			CORE_ADDR  = 13'h0999;

			// Check that CORE_WDATA is NOT on SRAM_WDATA
			@(posedge clk);
			check_core_wdata_blocked(32'h9999_9999, $sformatf("Word %0d: CORE_WDATA blocked", word_idx));
		end
	end

	// Wait for load_done
	$display("  Waiting for UART load to complete...");
	begin
		automatic int timeout = 0;
		// FIXED: Increased timeout slightly to comfortably fit entire payload transfer
		while (load_done !== 1'b1 && timeout < 1_000_000) begin
			@(posedge clk);
			timeout++;
		end
		if (load_done !== 1'b1)
			$display("[WARN] Timeout waiting for load_done");
		else
			$display("[INFO] UART load completed successfully");
	end

	// CRITICAL FIX: Deassert load_en immediately when load_done goes high
	load_en = 1'b0;

	// Wait for fw_load_en to deassert
	begin
		automatic int timeout = 0;
		while (fw_load_en !== 1'b0 && timeout < 100) begin
			@(posedge clk);
			timeout++;
		end
	end

	// ==============================================================
	// INTERLUDE: UART bad header test (between tests 2 and 3)
	// ==============================================================
	$display("\n--- INTERLUDE: UART Bad Header Test ---");
	$display("  Sending incorrect header to ensure header_fail asserts");

	master_reset();
	mode_sel = 2'b10;
	load_en  = 1'b1;
	wait_cycles(5);

	begin
		automatic int timeout = 0;
		while (fw_load_en !== 1'b1 && timeout < 100) begin
			@(posedge clk);
			timeout++;
		end
	end

	check_loaders_active("UART bad header: fw_load_en asserted");

	begin
		logic [31:0] bad_header;
		bad_header = {16'hDEAD, 16'd4};
		tb_current_header_sent = bad_header;

		$display("  Sending bad header word 0x%08h", bad_header);
		send_word_cts(bad_header);
	end

	load_en = 1'b0;

	check_header_fail_flag("UART bad header: header_fail response");
	clear_header_fail_after_delay();
	wait_cycles(20);

	begin
		automatic int timeout = 0;
		while (fw_load_en !== 1'b0 && timeout < 100) begin
			@(posedge clk);
			timeout++;
		end
	end

	// ==============================================================
	// PHASE 2: POST-UART LOAD - Core writes to SRAM
	//   load_en = 0, send CORE_ADDR cycling from 0x800+
	//   CORE_WDATA = 0x10000000, 0x20000000, 0x30000000, etc.
	//   Decoder should emit the word-aligned address CORE_ADDR[N+1:2]
	//   Each data value held for 50 cycles
	// ==============================================================
	$display("\n--- PHASE 2: Core Write Test (after UART load) ---");
	$display("  load_en=0, CORE_ADDR cycles from 0x800 onwards");
	$display("  CORE_WDATA cycles 0x10000000, 0x20000000, etc.");
	$display("  Decoder should translate addresses: CORE_ADDR[N+1:2]");
	$display("  Each data value held for 50 cycles");

	wait_cycles(10);

	check_loaders_inactive("Post-UART: loaders inactive");

	core_decoder_en = 1'b1;  // Enable address decoding for core

	// Now SRAM_WDATA should follow CORE_WDATA
	for (int core_idx = 0; core_idx < 10; core_idx++) begin
		logic [31:0] expected_wdata;
		logic [N-1:0] expected_addr;

		CORE_ADDR  = 32'h0000_0800 + (core_idx * 4); // 0x800, 0x804, 0x808, etc.
		expected_wdata = 32'h1000_0000 * (core_idx + 1); // 0x10000000, 0x20000000, etc.
		CORE_WDATA = expected_wdata;

		// Expected decoded address = CORE_ADDR word address
		expected_addr = CORE_ADDR[N+1:2];

		// Hold for 50 cycles and check at the beginning
		@(posedge clk);
		#1;

		// Check WDATA passthrough
		if (SRAM_WDATA === expected_wdata) begin
			$display("[PASS] Core write %0d: CORE_ADDR=0x%04h CORE_WDATA=0x%08h => SRAM_WDATA=0x%08h",
				 core_idx, CORE_ADDR, CORE_WDATA, SRAM_WDATA);
			pass_count = pass_count + 1;
		end else begin
			$display("[FAIL] Core write %0d: CORE_ADDR=0x%04h CORE_WDATA=0x%08h => SRAM_WDATA=0x%08h (exp 0x%08h)",
				 core_idx, CORE_ADDR, CORE_WDATA, SRAM_WDATA, expected_wdata);
			fail_count = fail_count + 1;
		end

		// Check address decode
		if (decoded_SRAM_ADDR === expected_addr) begin
			$display("[PASS] Core write %0d: decoded_SRAM_ADDR=0x%04h (exp 0x%04h)",
				 core_idx, decoded_SRAM_ADDR, expected_addr);
			pass_count = pass_count + 1;
		end else begin
			$display("[FAIL] Core write %0d: decoded_SRAM_ADDR=0x%04h (exp 0x%04h)",
				 core_idx, decoded_SRAM_ADDR, expected_addr);
			fail_count = fail_count + 1;
		end

		// Hold data for remaining 4999 cycles (total 5000 cycles per value)
		wait_cycles(4999);
	end

	// ==============================================================
	// SUMMARY
	// ==============================================================
	$display("\n================================================================");
	$display(" RESULTS: %0d PASSED, %0d FAILED (total %0d)",
		 pass_count, fail_count, pass_count + fail_count);

	if (fail_count == 0)
		$display(" ALL TESTS PASSED");
	else
		$display(" %0d TEST(S) FAILED", fail_count);
	$display("================================================================");

	#100;
	$finish;
	end

	//-------------------------------------//
	// Timeout watchdog
	//-------------------------------------//
	initial begin
		#(500_000_000); // 500 ms
		$display("[TIMEOUT] Simulation exceeded 500ms limit");
		$finish;
	end

endmodule