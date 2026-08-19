`timescale 1ns/1ps
///////////////////////////////////////////////////////////////////////////////////////////////////
// Engineer: Shashank Tiwari, Samyak Nidhi
// Update Date: 27.03.2026
// Module Name: tb_byte_acc (Custom RTL)
// Project Name: Silicon SoC rev 1.0
// Description:
// Testbench for verifying byte_accumulator functioning
// Test order:
// Sending bytes via fifo(not parallel fifo) check whether  4 of these become one word output o_fifo_word
///////////////////////////////////////////////////////////////////////////////////////////////////

module tb_byte_acc;

	// ============================================================
	// Clock & Reset
	// ============================================================
	logic i_clk;
	logic i_rst_n;

	// ============================================================
	// DUT Inputs
	// ============================================================
	logic        UART_rd_en;
	logic [7:0]  i_fifo8_rd_data;
	logic        i_fifo8_full;
	logic        i_fifo8_empty;
	logic        i_rx_error;

	// ============================================================
	// DUT Outputs
	// ============================================================
	logic [31:0] o_fifo_word;
	logic        o_fifo8_rd_en;
	logic        word_read_done;

	// ============================================================
	// DUT Instance
	// ============================================================
	byte_acc dut (
		.i_clk(i_clk),
		.i_rst_n(i_rst_n),
		.UART_rd_en(UART_rd_en),
		.i_fifo8_rd_data(i_fifo8_rd_data),
		.i_fifo8_empty(i_fifo8_empty),
		.i_rx_error(i_rx_error),
		.o_fifo_word(o_fifo_word),
		.o_fifo8_rd_en(o_fifo8_rd_en),
		.word_read_done(word_read_done)
	);

	// ============================================================
	// Clock generation : 100 MHz
	// ============================================================
	always #5 i_clk = ~i_clk;

	// ============================================================
	// FIFO MODEL (single-clock, safe)
	// ============================================================
	byte fifo_mem [0:31];
	int  rd_ptr;
	int  wr_ptr;
	int  fifo_depth;

	logic fifo_wr_en;
	byte  fifo_wr_data;

	always @(posedge i_clk) begin
		if (!i_rst_n) begin
			rd_ptr      <= 0;
			wr_ptr      <= 0;
			fifo_depth <= 0;
		end
		else begin
			// WRITE
			if (fifo_wr_en && fifo_depth < 32) begin
				fifo_mem[wr_ptr] <= fifo_wr_data;
				wr_ptr <= wr_ptr + 1;
				fifo_depth <= fifo_depth + 1;
			end

			// READ
			if (o_fifo8_rd_en && fifo_depth > 0) begin
				rd_ptr <= rd_ptr + 1;
				fifo_depth <= fifo_depth - 1;
			end
		end
	end

	assign i_fifo8_empty   = (fifo_depth == 0);
	assign i_fifo8_full    = (fifo_depth == 32);
	assign i_fifo8_rd_data = fifo_mem[rd_ptr];

	// ============================================================
	// FIFO PUSH TASK
	// ============================================================
	task fifo_push(input byte data);
		begin
			@(posedge i_clk);
			fifo_wr_data <= data;
			fifo_wr_en   <= 1'b1;
			@(posedge i_clk);
			fifo_wr_en   <= 1'b0;
		end
	endtask

	// ============================================================
	// UART WORD REQUEST TASK
	// ============================================================
	task request_word;
		begin
			@(posedge i_clk);
			UART_rd_en <= 1'b1;
			@(posedge i_clk);
			UART_rd_en <= 1'b0;
		end
	endtask

	// ============================================================
	// Assertions
	// ============================================================
	property rd_en_one_cycle;
		@(posedge i_clk)
			o_fifo8_rd_en |=> !o_fifo8_rd_en;
	endproperty
	assert property (rd_en_one_cycle)
		else $error("ERROR: o_fifo8_rd_en wider than 1 cycle");

	property no_read_when_empty;
		@(posedge i_clk)
			o_fifo8_rd_en |-> !i_fifo8_empty;
	endproperty
	assert property (no_read_when_empty)
		else $error("ERROR: rd_en asserted while FIFO empty");

	// ============================================================
	// Test Sequence
	// ============================================================
	initial begin
		i_clk        = 0;
		i_rst_n      = 0;
		UART_rd_en   = 0;
		i_rx_error   = 0;
		fifo_wr_en   = 0;
		fifo_wr_data = 0;

		// Reset
		repeat (3) @(posedge i_clk);
		i_rst_n = 1;

		// ==========================================================
		// WORD 1 : 11 22 33 44
		// ==========================================================
		fifo_push(8'h11);
		fifo_push(8'h22);
		fifo_push(8'h33);
		fifo_push(8'h44);

		request_word();
		repeat (10) @(posedge i_clk);

		if (o_fifo_word !== 32'h11_22_33_44)
			$error("FAIL W1: got %h", o_fifo_word);
		else
			$display("PASS W1: %h", o_fifo_word);

		// ==========================================================
		// WORD 2 : AA BB CC DD
		// ==========================================================
		fifo_push(8'hAA);
		fifo_push(8'hBB);
		fifo_push(8'hCC);
		fifo_push(8'hDD);

		request_word();
		repeat (10) @(posedge i_clk);

		if (o_fifo_word !== 32'hAA_BB_CC_DD)
			$error("FAIL W2: got %h", o_fifo_word);
		else
			$display("PASS W2: %h", o_fifo_word);

		// ==========================================================
		// WORD 3 : 01 02 03 04
		// ==========================================================
		fifo_push(8'h01);
		fifo_push(8'h02);
		fifo_push(8'h03);
		fifo_push(8'h04);

		request_word();
		repeat (10) @(posedge i_clk);

		if (o_fifo_word !== 32'h01_02_03_04)
			$error("FAIL W3: got %h", o_fifo_word);
		else
			$display("PASS W3: %h", o_fifo_word);

		// ==========================================================
		$display("ALL MULTI-WORD TESTS PASSED");
		$finish;
	end

endmodule
