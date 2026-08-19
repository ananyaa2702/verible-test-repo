`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Rohith Suju
// Create Date: 23.06.2026 11:01:22
// Module Name: tb_flash_standalone
// Project Name: kNN Silicon Front-End
// Description:
// Testbench for the flash standalone mode of the QFlexpress subsystem. This
// testbench initializes the QFlexpress subsystem, performs read and write
// operations to the flash memory, and verifies the functionality of the system.
//////////////////////////////////////////////////////////////////////////////////

`define SPANSION_MODEL
	// `define BASYS_3
	`define ARTY_A7

module tb_flash_standalone ();

  // 1. Changed TB inputs from 'wire' to 'reg' so we can drive them in tasks
  reg         clk;
  reg         resetn;
  reg         i_wb_cyc;
  reg         i_wb_stb;
  reg         i_wb_ctrl_stb;
  reg         i_wb_we;
  reg  [21:0] i_wb_addr;
  reg  [31:0] i_wb_wdata;

  wire        o_wb_stall;
  wire        o_wb_ack;
  wire [31:0] o_wb_data;
  wire        o_qspi_sck;
  wire        o_qspi_cs_n;
  wire qspi_io_3;
  wire qspi_io_2;
  wire qspi_io_1;
  wire qspi_io_0;
  wire flash_magic_word;

  // Clock Generation (100 MHz)
  always #5 clk = ~clk;

  qflexpress_subsystem u_qflexpress_subsystem (
      .clk          (clk),
      .resetn       (resetn),
      .i_wb_cyc     (i_wb_cyc),
      .i_wb_stb     (i_wb_stb),
      .i_wb_ctrl_stb(i_wb_ctrl_stb),
      .i_wb_we      (i_wb_we),
      .i_wb_addr    (i_wb_addr),
      .i_wb_wdata   (i_wb_wdata),
      .o_wb_stall   (o_wb_stall),
      .o_wb_ack     (o_wb_ack),
      .o_wb_data    (o_wb_data),
      .o_qspi_sck   (o_qspi_sck),
      .o_qspi_cs_n  (o_qspi_cs_n),
      .qspi_io_3    (qspi_io_3),
      .qspi_io_2    (qspi_io_2),
      .qspi_io_1    (qspi_io_1),
      .qspi_io_0    (qspi_io_0),
      .flash_magic_word(flash_magic_word)
  );

`ifdef SPANSION_MODEL
`ifdef ARTY_A7
	s25fl128s flash_mem (
     		.SCK(o_qspi_sck),
     		.CSNeg(o_qspi_cs_n),
     		.RSTNeg(resetn),
     		.SI(qspi_io_0),
     		.SO(qspi_io_1),
     		.WPNeg(qspi_io_2),
     		.HOLDNeg(qspi_io_3)
 	);
`endif
`ifdef BASYS_3
	s25fl032p flash_mem (
     		.SCK(o_qspi_sck),
		.SI(qspi_io_0),
		.CSNeg(o_qspi_cs_n),
		.HOLDNeg(qspi_io_3),
     		.WPNeg(qspi_io_2),
		.SO(qspi_io_1)
 	);
`endif
`else
    	W25Q16JV flash_mem (
        	.CSn  (o_qspi_cs_n),
        	.CLK  (o_qspi_sck),
        	.DIO  (qspi_io_0),
        	.DO   (qspi_io_1),
        	.WPn  (qspi_io_2),
        	.HOLDn(qspi_io_3)
    	);
`endif

  // ====================================================================
  // WISHBONE CFG TASKS
  // ====================================================================

  task wb_write;
    input bit cfg_port;
    input [21:0] addr;
    input [31:0] data;
    input integer delay_clks;
    begin
      @(posedge clk);
      #1;  // 1ns post-edge offset to make Vivado waveforms readable & fix hold times
      i_wb_cyc      = 1'b1;
      i_wb_stb      = 1'b1;
      i_wb_ctrl_stb = cfg_port;  // <-- Asserting CFG strobe
      i_wb_we       = 1'b1;
      i_wb_addr     = addr;
      i_wb_wdata    = data;

      // Wishbone Handshake: Hold until slave issues ACK
      forever begin
        @(posedge clk);
        if (o_wb_ack) break;
      end

      // Tear down bus
      #1;
      i_wb_cyc      = 1'b0;
      i_wb_stb      = 1'b0;
      i_wb_ctrl_stb = 1'b0;
      i_wb_we       = 1'b0;
      i_wb_wdata    = 32'hx;

      repeat (delay_clks) @(posedge clk);
    end
  endtask

  task wb_read;
    input bit cfg_port;
    input [21:0] addr;
    output [31:0] read_val;
    input integer delay_clks;
    begin
      @(posedge clk);
      #1;
      i_wb_cyc      = 1'b1;
      i_wb_stb      = 1'b1;
      i_wb_ctrl_stb = cfg_port;
      i_wb_we       = 1'b0;  // Read
      i_wb_addr     = addr;

      forever begin
        @(posedge clk);
        if (o_wb_ack) begin
          read_val = o_wb_data;
          break;
        end
      end

      #1;
      i_wb_cyc      = 1'b0;
      i_wb_stb      = 1'b0;
      i_wb_ctrl_stb = 1'b0;

      repeat (delay_clks) @(posedge clk);
    end
  endtask

  // ====================================================================
  // TEST SEQUENCE
  // ====================================================================

  reg [31:0] captured_data;

  task exit_xip;
    $display("[%0t] Exiting XIP mode...", $time);
    wb_write(1, 22'h0, 32'h0000_10FF, 0); // Unknown cmd to exit XIP mode
    //wb_write(1, 22'h0, 32'h0000_10FF, 0);
    wb_write(1, 22'h0, 32'h0000_1100, 'h3F); // set CS high
  endtask
  ;

  task enable_xip;
    $display("[%0t] Enabling Quad XIP mode...", $time);
    wb_write(1, 22'h0, 32'h0000_1006, 0); // Write Enable cmd
    wb_write(1, 22'h0, 32'h0000_1100, 0); // set CS high

    wb_write(1, 22'h0, 32'h0000_1001, 0); // WRR (Write registers) (01h)
    wb_write(1, 22'h0, 32'h0000_1000, 0); // Status Reg 1 = 0b0
    wb_write(1, 22'h0, 32'h0000_1002, 0); // Cfg Reg = 0b10 (Quad enable = 1)
    wb_write(1, 22'h0, 32'h0000_1100, 0); // set CS high

    // Poll WIP bit in Status Reg 1 (SR1[0]) until it is cleared
    wb_write(1, 22'h0, 32'h0000_1005, 0); // Read Status Reg 1 (05h)
    while(1) begin
      wb_write(1, 22'h0, 32'h0000_1000, 0); // Send empty bytes
      wb_read(1, 22'h0000_0000, captured_data, 5);
      if (captured_data[0] == 1'b0) begin
        break; // WIP bit cleared
      end
    end
    wb_write(1, 22'h0, 32'h0000_1100, 0); // set CS high

    wb_write(1, 22'h0, 32'h0000_10EB, 0); // Quad I/O read (EBh)
    wb_write(1, 22'h0, 32'h0000_1A00, 0); // 24 bit address
    wb_write(1, 22'h0, 32'h0000_1A00, 0);
    wb_write(1, 22'h0, 32'h0000_1A00, 0);
    wb_write(1, 22'h0, 32'h0000_1AA0, 0); // Mode byte  0xAX
    wb_write(1, 22'h0, 32'h0000_1800, 0); // 4 Dummy cycles
    wb_write(1, 22'h0, 32'h0000_1800, 0);
    wb_write(1, 22'h0, 32'h0000_1800, 0); // Read byte
    wb_write(1, 22'h0, 32'h0000_1800, 0);

    //wb_write(1, 22'h0, 32'h0000_1000, 0);
    wb_write(1, 22'h0, 32'h0000_0100, 0); // set CS high and turn off config mode
  endtask

  task test_read_id;
    $display("[%0t] Sending read ID cmd...", $time);

    wb_write(1, 22'h0, 32'h0000_109f, 0);

    wb_write(1, 22'h0, 32'h0000_1000, 0);
    wb_read(1, 22'h0000_0000, captured_data, 0);
    $display("[%0t] ReadID[0]: 0x%h", $time, captured_data[7:0]);

    wb_write(1, 22'h0, 32'h0000_1000, 0);
    wb_read(1, 22'h0000_0000, captured_data, 5);
    $display("[%0t] ReadID[1]: 0x%h", $time, captured_data[7:0]);

    wb_write(1, 22'h0, 32'h0000_1000, 0);
    wb_read(1, 22'h0000_0000, captured_data, 5);
    $display("[%0t] ReadID[2]: 0x%h", $time, captured_data[7:0]);

    wb_write(1, 22'h0, 32'h0000_1100, 0);  // set CS high again

  endtask

  task test_read_unique_id;
    // This is OTP read on Spansion
    $display("[%0t] Sending Read Unique ID cmd...", $time);

    wb_write(1, 22'h0, 32'h0000_104B, 0);
    wb_write(1, 22'h0, 32'h0000_1000, 0);
    wb_write(1, 22'h0, 32'h0000_1000, 0);
    wb_write(1, 22'h0, 32'h0000_1000, 0);
    wb_write(1, 22'h0, 32'h0000_1000, 0);


    for (int i = 0; i < 8; i++) begin
      wb_write(1, 22'h0, 32'h0000_1000, 0);
      wb_read(1, 22'h0000_0000, captured_data, 5);
      $display("[%0t] UniqueID[%0d]: 0x%h", $time, i, captured_data[7:0]);
    end

    wb_write(1, 22'h0, 32'h0000_1100, 0);  // set CS high again
  endtask

  task test_xip_read;
    input integer n_bytes;
    begin
      for (int i = 0; i < n_bytes; i++) begin
        wb_read(0, i, captured_data, 5);
        $display("[%0t] XIP Read[%0d]: 0x%h", $time, i, captured_data);
      end
    end
  endtask

  task test_spi_read();
    wb_write(1, 22'h0, 32'h0000_1003, 0);
    wb_write(1, 22'h0, 32'h0000_1000, 0);
    wb_write(1, 22'h0, 32'h0000_1000, 0);
    wb_write(1, 22'h0, 32'h0000_1000, 0);


    for (int i = 0; i < 10; i++) begin
      wb_write(1, 22'h0, 32'h0000_1000, 0);
      wb_read(1, 22'h0000_0000, captured_data, 5);
      $display("[%0t] SPI Read[%0d]: 0x%h", $time, i, captured_data[7:0]);
    end

    wb_write(1, 22'h0, 32'h0000_1100, 0);  // set CS high again
  endtask

  defparam u_qflexpress_subsystem.u_qflexpress.OPT_STARTUP = 0;

  reg maintenance;
  reg done_waiting;

  initial begin
    clk           = 0;
    resetn        = 0;
    i_wb_cyc      = 0;
    i_wb_stb      = 0;
    i_wb_ctrl_stb = 0;
    i_wb_we       = 0;
    i_wb_addr     = 0;
    i_wb_wdata    = 0;

    #100;
    resetn = 1;

    // CRITICAL: See Note 1 below regarding Dan Gisselquist's core!
    $display("[%0t] Reset released. Waiting for Controller 300us Wakeup...", $time);

    repeat (16000) @(posedge clk);
    done_waiting = 1;

    assign maintenance = u_qflexpress_subsystem.u_qflexpress.maintenance;

    //wait (maintenance == 1'b1);
    //wait (maintenance == 1'b0);

    enable_xip();
    exit_xip();
    test_read_id();
    test_read_unique_id();
    test_spi_read();
    enable_xip();
    test_xip_read(10);

    #1000;
    $finish;
  end

endmodule
