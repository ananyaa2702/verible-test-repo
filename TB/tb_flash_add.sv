`timescale 1ns / 1ps
///////////////////////////////////////////////////////////////////////////////////////////////////
// Engineer: Shashank Tiwari, Samyak Nidhi
// Update Date: 05.07.2026
// Module Name: tb_flash_add (SOC_V1.1)
// Project Name: Silicon SoC
// Description:
// Testbench for flash -> SRAM loading and execution (CPU-> sram) complete flow
// with simple addition firmware then writing back to address 0(0600_0000) of SRAM.
//
// NOTE: reset_synch has been removed for post-synthesis compatibility.
// master_resetn drives the system directly.
///////////////////////////////////////////////////////////////////////////////////////////////////

`define FAST_LOAD

module tb_flash_add;

	//-------------------------------------//
	// Parameters
	//-------------------------------------//
	localparam [1:0]   FLASH_MODE_SEL           = 2'b00;
	localparam [1:0]   UART_MODE_SEL            = 2'b10;
	localparam integer UART_CLKS_PER_BIT        = 434;
	localparam integer UART_PAYLOAD_WORDS       = 9;
	localparam integer FLASH_PAYLOAD_WORDS      = 70;
	localparam integer LOAD_DONE_TIMEOUT_CYCLES = 600000;
	localparam integer LOAD_DONE_GRACE_CYCLES   = 64;
	localparam integer APP_POSTLOAD_OBS_CYCLES  = 200000;
	localparam integer FLASH_DATA_BYTE_BASE     = 16'h0100;
	localparam integer RESET_SYNC_FF_COUNT      = 5;

	//-------------------------------------//
	// Firmware Payload (FFW)
	//-------------------------------------//
	localparam [31:0] FFW0  = 32'hB007_B007; // header magic
	localparam [31:0] FFW1  = 32'h0000_0108; // payload size (accomodate data bytes that are at 0x100)
	localparam [31:0] FFW2  = 32'h0600_0000; // load address: 0x0600_0000
	localparam [31:0] FFW3  = 32'h21AD_CB29; // payload checksum (including data)

	localparam [31:0] FFW4  = 32'h0600_09B7; // lui   s3, 0x6000
	localparam [31:0] FFW5  = 32'h0600_0A37; // lui   s4, 0x6000
	localparam [31:0] FFW6  = 32'h100A_0A13; // addi  s4, s4, 256 (0x100)
	localparam [31:0] FFW7  = 32'h000A_2B03; // lw    s6, 0(s4)
	localparam [31:0] FFW8  = 32'h004A_2B83; // lw    s7, 4(s4)
	localparam [31:0] FFW9  = 32'h017B_0B33; // add   s6, s6, s7
	localparam [31:0] FFW10 = 32'h0169_A023; // sw    s6, 0(s3) (store to sram)
	localparam [31:0] FFW11 = 32'h0100_0AB7; // lui   s5, 0x1000 (store to flash, assumes Quad XIP mode is enabled)
	localparam [31:0] FFW12 = 32'h016A_A023; // sw    s6, 0(s5)
	localparam [31:0] FFW13 = 32'h0000_006F; // j     hang (inf loop)

	/* * Below is the data that the flash helper firmware will read from flash and write to SRAM
	 * at address 0x0600_0000, then the app code will read this value from SRAM and write it
	 * back to flash as a way to verify the flash read/write functionality in the testbench.
	 * We are using a non-zero value here to make it easier to identify in the waveforms and logs.
	 */
	localparam [31:0] FDATA0 = 32'h0000_0001;
	localparam [31:0] FDATA1 = 32'h0000_0002;

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
	reg        switch   = 1'b0;
	reg  [1:0] mode_sel = 2'b00;
	reg        i_rx_tb  = 1'b1;

	//-------------------------------------//
	// DUT Interfacing Signals
	//-------------------------------------//
	wire       trap;
	wire [9:0] gpio_out;
	wire       load_busy;
	wire       load_done;
	wire       FW_loader_UART_o_rts;
	wire       FW_loader_UART_rx_error;
	wire       FW_loader_UART_check_start;
	wire       flash_magic_word; // magic_word match
	wire       header_fail;

	reg        CPU_CTS = 1'b0;
	reg        CPU_RTS;
	reg        pcpi_valid;
	reg        pcpi_ready;

	//-------------------------------------//
	// QSPI / Flash Signals
	//-------------------------------------//
	wire       SCK;
	wire       CS_N;
	wire       IO_data_3;
	wire       IO_data_2;
	wire       IO_data_1;
	wire       IO_data_0;

	reg        qspi_oe;      // 1: drive lines (write from flash), 0: release (read from flash)
	reg  [3:0] qspi_out;     // bits to drive on IO[3:0]
	wire [3:0] qspi_in;      // bits read from IO[3:0]

	//-------------------------------------//
	// Tracking Variables
	//-------------------------------------//
	reg [31:0] sram_mirror [0:4095];
	integer    k;
	integer    wait_cycles;
	integer    uart_writes_seen;
	integer    test_failures;
	integer    app_store_log_count;
	integer    app_ifetch_log_count;
	integer    boot_load_log_count;

	reg        flash_result_seen;
	reg        uart_result_seen;
	reg        flash_read_seen;
	reg        app_fetch_seen;
	reg        app_result_seen;
	reg        app_csr_write_seen;
	reg        trap_seen;

	//-------------------------------------//
	// Combinational Assignments
	//-------------------------------------//

	// Post-synth safe reset mapping
	assign resetn = master_resetn;

	// QSPI Lane mapping
	// When qspi_oe is 1 we drive the value of qspi_out on the IO lines, when it's 0 we release the lines to high impedance so that flash can drive them.
	// This is needed because in quad mode we use all 4 IO lines for both reading and writing and we need to control the direction of data flow.
	assign IO_data_0 = qspi_oe ? qspi_out[0] : 1'bz;
	assign IO_data_1 = qspi_oe ? qspi_out[1] : 1'bz;
	assign IO_data_2 = qspi_oe ? qspi_out[2] : 1'bz;
	assign IO_data_3 = qspi_oe ? qspi_out[3] : 1'bz;

	// Concatenate and assign
	assign qspi_in   = {IO_data_3, IO_data_2, IO_data_1, IO_data_0};

	/*
	 * Clock Generator
	 */
	always #5 clk = ~clk;

	//-------------------------------------//
	// DUT (System) Instantiation
	//-------------------------------------//
	system #(
		.FF_COUNT(RESET_SYNC_FF_COUNT)
	) uut (
		.clk                        (clk),
		.master_resetn              (master_resetn),
		.trap                       (trap),
		.gpio_out                   (gpio_out),
		.load_en_asynch             (load_en),
		.FW_loader_UART_i_rx        (i_rx_tb),
		.mode_sel_asynch            (mode_sel),
		.load_busy                  (load_busy),
		.load_done                  (load_done),
		.FW_loader_UART_o_rts       (FW_loader_UART_o_rts),
		.FW_loader_UART_rx_error    (FW_loader_UART_rx_error),
		.FW_loader_UART_check_start (FW_loader_UART_check_start),
		.o_qspi_sck                 (SCK),
		.o_qspi_cs_n                (CS_N),
		.qspi_io_3                  (IO_data_3),
		.qspi_io_2                  (IO_data_2),
		.qspi_io_1                  (IO_data_1),
		.qspi_io_0                  (IO_data_0),
		.flash_magic_word           (flash_magic_word),
		.CPU_UART_TRANSCEIVER_TX    ( ),
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
	// The off-chip flash model, connected to the SoC's SPI/QSPI pins
 	W25Q16JV flash_mem (
        	.CSn   (CS_N),
        	.CLK   (SCK),
        	.DIO   (IO_data_0),
        	.DO    (IO_data_1),
        	.WPn   (IO_data_2),
        	.HOLDn (IO_data_3)
 	);

	//-------------------------------------//
	// QSPI / Flash Tasks
	//-------------------------------------//

	/*
	 * Simple SDR clock helper
	 * Basically mimicing flash clock behaviour
	 */
	task automatic qspi_clk_tick;
	begin
		@(posedge clk);
	end
	endtask

	/*
	 * Send one 4-bit payload over 4 IO lines in one clock
	 * 4 bits of data to the four IO in the quad mode in one clock cycle
	 */
	task automatic qspi_send_nibble(input [3:0] nib);
	begin
		qspi_oe  = 1'b1;
		qspi_out = nib;          // nib[3]->IO3 ... nib[0]->IO0
		qspi_clk_tick();
	end
	endtask

	/*
	 * Send one byte from FFW localparams in quad mode: 2 clocks
	 * 2 clock cycles to send one FFW word.
	 * ffw_word_idx: 0..12 maps to FFW0..FFW12
	 * byte_in_word: 0..3 maps to [31:24], [23:16], [15:8], [7:0]
	 */
	task automatic qspi_send_byte_quad(input integer ffw_word_idx, input integer byte_in_word);
	reg [31:0] ffw_word;
	reg [7:0]  byte_val;
	begin
		ffw_word = ffw_word_at(ffw_word_idx);

		case (byte_in_word)
			0: byte_val = ffw_word[31:24];
			1: byte_val = ffw_word[23:16];
			2: byte_val = ffw_word[15:8];
			3: byte_val = ffw_word[7:0];
			default: byte_val = 8'h00;
		endcase

		qspi_send_nibble(byte_val[7:4]); // first transfer
		qspi_send_nibble(byte_val[3:0]); // second transfer
	end
	endtask

	/*
	 * Convenience task: send full FFW payload (13 words x 4 bytes = 52 bytes)
	 * Call the previous task in loop and send all 13 FFW words in 26 cycles
	 */
	task automatic qspi_send_all_ffw_quad;
	integer wi;
	integer bi;
	begin
		for (wi = 0; wi < FLASH_PAYLOAD_WORDS; wi = wi + 1)
			for (bi = 0; bi < 4; bi = bi + 1)
				qspi_send_byte_quad(wi, bi);
	end
	endtask

	/*
	 * Read one byte in quad mode: 2 clocks
	 * 2 clocks to read from flash
	 */
	task automatic qspi_read_byte_quad(output [7:0] b);
	reg [3:0] hi, lo;
	begin
		qspi_oe = 1'b0;          // release IO lines so flash can drive
		qspi_clk_tick(); hi = qspi_in;
		qspi_clk_tick(); lo = qspi_in;
		b = {hi, lo};
	end
	endtask

	/*
	 * FFW word index function
	 * The tasks use this indexed FFW word so that if index 0 we send FFW 0 itself and so on
	 */
	function automatic [31:0] ffw_word_at;
		input integer idx;
		begin
			case (idx)
				0:  ffw_word_at = FFW0;
				1:  ffw_word_at = FFW1;
				2:  ffw_word_at = FFW2;
				3:  ffw_word_at = FFW3;
				4:  ffw_word_at = FFW4;
				5:  ffw_word_at = FFW5;
				6:  ffw_word_at = FFW6;
				7:  ffw_word_at = FFW7;
				8:  ffw_word_at = FFW8;
				9:  ffw_word_at = FFW9;
				10: ffw_word_at = FFW10;
				11: ffw_word_at = FFW11;
				12: ffw_word_at = FFW12;
				13: ffw_word_at = FFW13;
				default: ffw_word_at = 32'h0000_0000;
			endcase
		end
	endfunction

	/*
	 * Program flash model memory at runtime (no macro-file dependency for payload content).
	 * Instead of using MEM_16Mb we are using this task to directly write to flash mem
	 */
	task automatic program_flash_runtime_from_ffw;
		integer i;
		integer base;
		reg [31:0] w;
		begin
			for (i = 0; i < FLASH_PAYLOAD_WORDS; i = i + 1)
			begin
				w = ffw_word_at(i); // using the index function
				base = i * 4;

				// little endian
				flash_mem.memory[base + 0] = w[7:0]; // writing the 32 bit thing 1 word at a time
				flash_mem.memory[base + 1] = w[15:8]; // this is for instructions only
				flash_mem.memory[base + 2] = w[23:16];
				flash_mem.memory[base + 3] = w[31:24];
			end

			// Keep raw constants in a separate data region, not in instruction stream.
			// Header is 16 bytes, account for it so data ends up at 0x100 offset in SRAM
			base = FLASH_DATA_BYTE_BASE + 16;
			w = FDATA0;

			// Writing everything in little endian
			flash_mem.memory[base + 0] = w[7:0]; // this is for the data
			flash_mem.memory[base + 1] = w[15:8];
			flash_mem.memory[base + 2] = w[23:16];
			flash_mem.memory[base + 3] = w[31:24];

			base = base + 4;
			w = FDATA1;
			flash_mem.memory[base + 0] = w[7:0];
			flash_mem.memory[base + 1] = w[15:8];
			flash_mem.memory[base + 2] = w[23:16];
			flash_mem.memory[base + 3] = w[31:24];
		end
	endtask

	/*
	 * Sanity check: verify model memory bytes contain the expected FFW words.
	 * Reading back from flash mem to check if above task worked
	 */
	task automatic dump_flash_runtime_words;
		integer i;
		integer base;
		reg [31:0] got;
		reg [31:0] exp;
		begin
			for (i = 0; i < FLASH_PAYLOAD_WORDS; i = i + 1)
			begin
				base = i * 4;
				got = {flash_mem.memory[base + 0], flash_mem.memory[base + 1], flash_mem.memory[base + 2], flash_mem.memory[base + 3]};
				exp = ffw_word_at(i);
				$display("  [FLASH DUMP] Word %02d | got: 0x%08h | exp: 0x%08h", i, got, exp);
			end
		end
	endtask

	//-------------------------------------//
	// Execution Trackers
	//-------------------------------------//
	/*
	 * App execution markers:
	 * 1) Core fetches instructions from SRAM app region (0x0600_xxxx)
	 * 2) Core commits arithmetic result 3 to SRAM base address 0x0600_0000
	 * 3) Core commits CSR done write 4 to 0x0020_0000
	 *
	 * Logging the instructions that core is fetching to see whether what was written
	 * in sram is same as the app software we sent through flash (here is where bridge fail
	 * came up and we added the latching)
	 */
	always @(posedge clk)
	begin
		if (!resetn)
		begin
			flash_read_seen      <= 1'b0;
			app_fetch_seen       <= 1'b0;
			app_result_seen      <= 1'b0;
			app_csr_write_seen   <= 1'b0;
			app_store_log_count  <= 0;
			app_ifetch_log_count <= 0;
			boot_load_log_count  <= 0;
			trap_seen            <= 1'b0;
		end
		else
		begin
			if (!app_fetch_seen && uut.mem_valid && uut.mem_ready && !uut.mem_instr && !(|uut.mem_wstrb) && (boot_load_log_count < 32))
			begin
				$display("[%0t] [BOOT LOAD] addr: 0x%08h | data: 0x%08h", $time, uut.mem_addr, uut.mem_rdata);
				$display("[%0t] [BOOT DBG]  spi_vld:%0b flsh_rdy:%0b flsh_rdata:0x%08h brom_vld:%0b brom_rdata:0x%08h wb_ack:%0b wb_stl:%0b wb_st:%0d rsp_pnd:%0b",
						 $time, uut.spi_mem_valid, uut.flash_ready, uut.flash_rdata, uut.bootrom_valid, uut.bootrom_rdata,
						 uut.core_wb_bridge.o_wb_ack, uut.core_wb_bridge.o_wb_stall, uut.core_wb_bridge.state, uut.core_wb_bridge.rsp_pending);
				boot_load_log_count <= boot_load_log_count + 1;
			end

			if (uut.mem_valid && uut.mem_ready && !uut.mem_instr && !(|uut.mem_wstrb) &&
				(uut.mem_addr >= 32'h0100_0000) && (uut.mem_addr <= 32'h01FF_FFFF))
			begin
				if (!flash_read_seen)
					$display("[%0t] [FLASH_RD]  Window read observed at addr: 0x%08h | data: 0x%08h", $time, uut.mem_addr, uut.mem_rdata);
				flash_read_seen <= 1'b1;
			end

			if (uut.mem_valid && uut.mem_ready && uut.mem_instr &&
				(uut.mem_addr >= 32'h0600_0000) && (uut.mem_addr <= 32'h0600_00FF))
			begin
				if (!app_fetch_seen)
					$display("\\n[%0t] >>> [APP EXEC] Core started fetching from SRAM app region", $time);

				// if it writes to any of the location within sram then we can be sure that it succeeded
				// in the full flow of Flash->qflex->wb->sram(via core)->core execution
				app_fetch_seen <= 1'b1;

				if (app_ifetch_log_count < 16)
				begin
					$display("[%0t] [APP IFETCH] addr: 0x%08h | instr: 0x%08h", $time, uut.mem_addr, uut.mem_rdata);
					app_ifetch_log_count <= app_ifetch_log_count + 1; // printing all the instructions that core is fetching
				end
			end

			if (uut.mem_valid && uut.mem_ready && !uut.mem_instr && (|uut.mem_wstrb))
			begin
				if ((uut.mem_addr >= 32'h0600_0000) && (uut.mem_addr <= 32'h0600_00FF) && (app_store_log_count < 16))
				begin
					$display("[%0t] [APP STORE] addr: 0x%08h | data: 0x%08h | strb: %4b", $time, uut.mem_addr, uut.mem_wdata, uut.mem_wstrb);
					app_store_log_count <= app_store_log_count + 1; // here checking if core is writing back to sram
				end

				if ((uut.mem_addr == 32'h0600_0000) && (uut.mem_wdata == 32'h0000_0003))
				begin
					if (!app_result_seen)
						$display("[%0t] >>> [APP RESULT] Core wrote result 0x00000003 to 0x06000000", $time);

					// since our fw team is writing to 0600_0000 we test whether it is storing 3 here
					app_result_seen <= 1'b1;
				end

				if ((uut.mem_addr == 32'h0020_0000) && (uut.mem_wdata == 32'h0000_0004))
				begin
					if (!app_csr_write_seen)
						$display("[%0t] >>> [APP CSR] Core wrote done value 0x00000004 to 0x00200000", $time);

					// this is to check that csr for sram is writing 4 to 0x0020_0000 if this happens
					// only then we can be sure that bootrom finished correctly
					app_csr_write_seen <= 1'b1;
				end
			end

			if (uut.sram_wea_core && uut.sram_valid_core &&
				(uut.SRAM_ADDR_RAW == 32'h0600_0000) && (uut.SRAM_WDATA == 32'h0000_0003))
			begin
				if (!app_result_seen)
					$display("[%0t] >>> [APP RESULT] Core wrote result 0x00000003 to 0x06000000", $time);
				app_result_seen <= 1'b1;
			end

			if (trap && !trap_seen)
			begin
				$display("[%0t] >>> [TRAP] Trap asserted | addr: 0x%08h | rdata: 0x%08h", $time, uut.mem_addr, uut.mem_rdata);
				trap_seen <= 1'b1;
			end
		end
	end

	//-------------------------------------//
	// Pre-load BootROM
	//-------------------------------------//
	`ifdef FAST_LOAD
	initial
	begin
		// Wait a brief moment for the IP's internal logic to settle
		#1;

		// Inject the new firmware directly into the simulation array change this for fast bootrom loading
		$readmemh("bootrom_flash_add_tb.memh",
			uut.u_bootrom_wrapper.bootrom.inst.native_mem_module.blk_mem_gen_v8_4_12_inst .memory);

		$display("TB_NOTE: Fast-loaded custom firmware into BootROM bypassing synthesis!");
	end
	`endif

	//-------------------------------------//
	// Main Test Sequence
	//-------------------------------------//
	initial
	begin
		$display("================================================================");
		$display(" TB: tb_flash_add");
		$display("================================================================");

		// Basic flash-load bring-up sequence.
		master_resetn        = 1'b0;
		load_en              = 1'b0;
		mode_sel             = FLASH_MODE_SEL;
		qspi_oe              = 1'b0;
		qspi_out             = 4'h0;

		wait_cycles          = 0;
		uart_writes_seen     = 0;
		test_failures        = 0;
		app_store_log_count  = 0;
		app_ifetch_log_count = 0;
		boot_load_log_count  = 0;

		flash_result_seen    = 1'b0;
		uart_result_seen     = 1'b0;
		flash_read_seen      = 1'b0;
		app_fetch_seen       = 1'b0;
		app_result_seen      = 1'b0;
		app_csr_write_seen   = 1'b0;
		trap_seen            = 1'b0;

		repeat (20) @(posedge clk);
		master_resetn = 1'b1; // release reset

		// qflexpress startup/maintenance phase is on the order of hundreds of us.
		// Wait long enough so subsequent flash reads return actual payload data.
		repeat (40000) @(posedge clk);

		$display("\\n--- PHASE 1: Flash Programming ---");
		// Runtime application placement into flash model.
		program_flash_runtime_from_ffw(); // writing FFW words and data to flash mem
		$display("  Runtime flash programming complete for FFW payload.");
		dump_flash_runtime_words(); // testing the writes by reading back

		$display("\\n--- PHASE 2: Bootrom Flash Load ---");
		// Trigger boot controller flash load path.
		@(posedge clk); load_en = 1'b1; // then enabling core
		#20
		@(posedge clk); load_en = 1'b0;

		wait_cycles = 0;
		while (!load_done)
		begin // just a cycle count loop to avoid infintie runtime
			@(posedge clk);
			wait_cycles = wait_cycles + 1;
		end

		if (!load_done)
		begin
			repeat (LOAD_DONE_GRACE_CYCLES) @(posedge clk);
		end

		if (load_done)
		begin // the FFW got written into sram successfully and the boot controller signaled load done
			$display("[%0t] Firmware load completed successfully.", $time);
			wait_cycles = 0;
			while ((!flash_read_seen || !app_fetch_seen || !app_result_seen || !app_csr_write_seen) && wait_cycles < APP_POSTLOAD_OBS_CYCLES)
			begin
				@(posedge clk);
				wait_cycles = wait_cycles + 1;
			end
		end
		else
		begin
			$display("[%0t] [ERROR] Firmware load did not complete within expected time.", $time);
		end

		@(posedge clk); // allow marker flags to settle before summary print

		$display("\\n================================================================");
		$display(" APP EXECUTION SUMMARY");
		$display("================================================================");
		$display(" flash_read_seen    = %0d", flash_read_seen);
		$display(" app_fetch_seen     = %0d", app_fetch_seen);
		$display(" app_result_seen    = %0d", app_result_seen);
		$display(" app_csr_write_seen = %0d", app_csr_write_seen);
		$display(" trap_seen          = %0d", trap_seen);
		$display("----------------------------------------------------------------");

		if (load_done && flash_read_seen && app_fetch_seen && app_result_seen && app_csr_write_seen)
			$display(" ??? TEST PASS: bootrom bootstrap + flash load + SRAM execution path observed.");
		else
			$display(" ??? TEST FAIL: expected flash-load/execution markers not fully observed.");
		$display("================================================================\\n");

		$finish;
	end
endmodule