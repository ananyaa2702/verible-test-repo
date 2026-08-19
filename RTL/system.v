`timescale 1ns / 1ps
///////////////////////////////////////////////////////////////////////////////////////////////////
// Engineer: Rakesh Patil, Shashank Tiwari, Samyak Nidhi
// Update Date: 03.04.2026
// Module Name: system.v
// Project Name: Silicon SoC kNN
// Description:
// Top-level SoC integration module connecting the PicoRV32 core to on-chip and off-chip peripherals
// through a native memory-mapped interconnect.
// Integrated blocks include BootROM, SRAM, SPI flash controller (QSPI), UART transceiver path,
// GPIO output path, firmware-loader control path, and SRAM CSR/status path.
// Supports multi-source firmware loading (core-driven path and custom RTL loader paths such as UART/FIFO),
// with load status signaling (busy/done/error/header-check) exported for system monitoring.
// Implements address-space decoding and response multiplexing for BootROM, SRAM, SPI data/CSR, UART,
// GPIO, and SRAM CSR regions, including BRAM-style one-cycle ready generation where required.
// Includes remap-aware SRAM/BootROM decode behavior via core_bootrom_remap and address-decoder logic
// to support backup/boot modes without changing core-visible transaction semantics.
///////////////////////////////////////////////////////////////////////////////////////////////////

//modified version of system.v (2 separate Vivado BRAM IPs for bootrom and SRAM)
//memory mapped architecture (*Native interface based*)

`include "global_defines.v"

module system
#(
        parameter FF_COUNT = 3
) (
`ifdef FOR_ASIC
		input wire clk_pad,
		input wire master_resetn_pad,

		//------------------//
		// Core status I/O  //
		//------------------//
		output wire trap_pad,

		//------------------------//
		// GPIO output interface  //
		//------------------------//
		output wire [9:0] gpio_out_pad, // generic GPIO output bus

		//--------------------------------//
		// QSPI flash pin interface       //
		//--------------------------------//
		output wire	o_qspi_sck_pad, // SPI clock
		output wire	o_qspi_cs_n_pad, // active-low chip select
		inout  wire     qspi_io_3_pad,
		inout  wire     qspi_io_2_pad,
		inout  wire     qspi_io_1_pad,
		inout  wire     qspi_io_0_pad,
		output wire     flash_magic_word_pad, // Magic_word observability

		//----------------------------------//
		// UART transceiver pins            //
		//----------------------------------//
		output wire CPU_UART_TRANSCEIVER_TX_pad,
		input wire CPU_UART_TRANSCEIVER_RX_pad,
                output wire CPU_RTS_pad,
                input wire CPU_CTS_pad,


		//-------------------------//
		// Custom RTL control I/O  //
		//-------------------------//
		input wire load_en_asynch_pad, // global enable for custom loader path
		input wire FW_loader_UART_i_rx_pad,
		input wire [1:0] mode_sel_asynch_pad, // select load source: core/uart/fifo

		//--------------------------//
		// Loader status outputs    //
		//--------------------------//
		output wire FW_loader_UART_o_rts_pad,            // custom RTL UART RTS
		output wire load_busy_pad,        // asserted while load is active
		output wire load_done_pad,        // asserted when load completes
		output wire FW_loader_UART_check_start_pad, // UART start check flag
		output wire FW_loader_UART_rx_error_pad,    // UART stop-bit error
		output wire FW_loader_UART_header_fail_pad,       // header check failed

                //--------------------------------------//
                // Observability Pins from co-processor //
                //--------------------------------------//
                output wire pcpi_valid_pad,
                output wire pcpi_ready_pad
`else
		input wire clk,
		input wire master_resetn,

		//------------------//
		// Core status I/O  //
		//------------------//
		output wire trap,

		//------------------------//
		// GPIO output interface  //
		//------------------------//
		output wire [9:0] gpio_out, // generic GPIO output bus

		//--------------------------------//
		// QSPI flash pin interface       //
		//--------------------------------//
		/*
		output wire		o_qspi_sck,
		output wire		o_qspi_cs_n,
		output reg	[1:0]o_qspi_mod,
		output wire	[3:0]o_qspi_dat,
		input  wire	[3:0]i_qspi_dat
		*/

`ifndef FOR_FPGA_BOARD
		output wire	o_qspi_sck, // SPI clock
`endif
		output wire	o_qspi_cs_n, // active-low chip select
		inout  wire     qspi_io_3,
		inout  wire     qspi_io_2,
		inout  wire     qspi_io_1,
		inout  wire     qspi_io_0,
		output wire     flash_magic_word, // Magic_word observability

		//----------------------------------//
		// UART transceiver pins            //
		//----------------------------------//
		output wire CPU_UART_TRANSCEIVER_TX,
		input wire  CPU_UART_TRANSCEIVER_RX,
                output wire CPU_RTS,
                input wire CPU_CTS,

		//-------------------------//
		// Custom RTL control I/O  //
		//-------------------------//
		input wire load_en_asynch, // global enable for custom loader path
		input wire FW_loader_UART_i_rx,
		input wire [1:0] mode_sel_asynch, // select load source: core/uart/fifo

		//--------------------------//
		// Loader status outputs    //
		//--------------------------//
		output wire FW_loader_UART_o_rts,            // custom RTL UART RTS
		output wire load_busy,        // asserted while load is active
		output wire load_done,        // asserted when load completes
		output wire FW_loader_UART_check_start, // UART start check flag
		output wire FW_loader_UART_rx_error,    // UART stop-bit error
		output wire FW_loader_UART_header_fail,       // header check failed

                //--------------------------------------//
                // Observability Pins from co-processor //
                //--------------------------------------//
                output wire pcpi_valid,
                output wire pcpi_ready
`endif
);

`ifdef FOR_FPGA_BOARD
	wire o_qspi_sck;
`endif

`ifdef FOR_ASIC
// Pad assignments for ASIC implementation (using SCL180nm standard cell library)
wire clk, clk_intermediate;
wire master_resetn;
wire trap;
wire [9:0] gpio_out;
wire o_qspi_sck;
wire o_qspi_cs_n;
wire flash_magic_word;
wire CPU_UART_TRANSCEIVER_TX;
wire CPU_UART_TRANSCEIVER_RX;
wire CPU_RTS;
wire CPU_CTS;
wire load_en_asynch;
wire FW_loader_UART_i_rx;
wire [1:0] mode_sel_asynch;
wire FW_loader_UART_o_rts;
wire load_busy;
wire load_done;
wire FW_loader_UART_check_start;
wire FW_loader_UART_rx_error;
wire FW_loader_UART_header_fail;
wire pcpi_valid;
wire pcpi_ready;

wire [3:0] oe_dat_out;
wire [3:0] qspi_i;
wire [3:0] qspi_o;

pc3b05 pc3b05_qspi_io_3(.I(qspi_o[3]),.CIN(qspi_i[3]),.OEN(~oe_dat_out[3]),.PAD(qspi_io_3_pad));
pc3b05 pc3b05_qspi_io_2(.I(qspi_o[2]),.CIN(qspi_i[2]),.OEN(~oe_dat_out[2]),.PAD(qspi_io_2_pad));
pc3b05 pc3b05_qspi_io_1(.I(qspi_o[1]),.CIN(qspi_i[1]),.OEN(~oe_dat_out[1]),.PAD(qspi_io_1_pad));
pc3b05 pc3b05_qspi_io_0(.I(qspi_o[0]),.CIN(qspi_i[0]),.OEN(~oe_dat_out[0]),.PAD(qspi_io_0_pad));

pc3d01 pc3d01_FW_loader_UART_i_rx(.PAD (FW_loader_UART_i_rx_pad), .CIN (FW_loader_UART_i_rx));
pc3d01 pc3d01_resetn(.PAD (master_resetn_pad), .CIN (master_resetn));
pc3d01 pc3d01_load_en(.PAD (load_en_asynch_pad), .CIN (load_en_asynch));
pc3d01 pc3d01_CPU_UART_TRANSCEIVER_RX(.PAD (CPU_UART_TRANSCEIVER_RX_pad), .CIN (CPU_UART_TRANSCEIVER_RX));
pc3d01 pc3d01_mode_sel0(.PAD (mode_sel_asynch_pad[0]), .CIN (mode_sel_asynch[0]));
pc3d01 pc3d01_mode_sel1(.PAD (mode_sel_asynch_pad[1]), .CIN (mode_sel_asynch[1]));
pc3d01 pc3d01_CPU_CTS(.PAD (CPU_CTS_pad), .CIN (CPU_CTS));

pc3o05 pc3o05_FW_loader_UART_o_rts(.I (FW_loader_UART_o_rts), .PAD (FW_loader_UART_o_rts_pad));
pc3o05 pc3o05_o_qspi_sck(.I (o_qspi_sck), .PAD (o_qspi_sck_pad));
pc3o05 pc3o05_o_qspi_cs_n(.I (o_qspi_cs_n), .PAD (o_qspi_cs_n_pad));
pc3o05 pc3o05_trap(.I (trap), .PAD (trap_pad));
pc3o05 pc3o05_gpio_out0(.I (gpio_out[0]), .PAD (gpio_out_pad[0]));
pc3o05 pc3o05_gpio_out1(.I (gpio_out[1]), .PAD (gpio_out_pad[1]));
pc3o05 pc3o05_gpio_out2(.I (gpio_out[2]), .PAD (gpio_out_pad[2]));
pc3o05 pc3o05_gpio_out3(.I (gpio_out[3]), .PAD (gpio_out_pad[3]));
pc3o05 pc3o05_gpio_out4(.I (gpio_out[4]), .PAD (gpio_out_pad[4]));
pc3o05 pc3o05_load_busy(.I (load_busy), .PAD (load_busy_pad));
pc3o05 pc3o05_load_done(.I (load_done), .PAD (load_done_pad));
pc3o05 pc3o05_FW_loader_UART_check_start(.I (FW_loader_UART_check_start), .PAD (FW_loader_UART_check_start_pad));
pc3o05 pc3o05_FW_loader_UART_rx_error(.I (FW_loader_UART_rx_error), .PAD (FW_loader_UART_rx_error_pad));
pc3o05 pc3o05_FW_loader_UART_header_fail(.I (FW_loader_UART_header_fail), .PAD (FW_loader_UART_header_fail_pad));
pc3o05 pc3o05_CPU_UART_TRANSCEIVER_TX(.I (CPU_UART_TRANSCEIVER_TX), .PAD (CPU_UART_TRANSCEIVER_TX_pad));
pc3o05 pc3o05_CPU_RTS(.I (CPU_RTS), .PAD (CPU_RTS_pad));
pc3o05 pc3o05_gpio_out5(.I (gpio_out[5]), .PAD (gpio_out_pad[5]));
pc3o05 pc3o05_gpio_out6(.I (gpio_out[6]), .PAD (gpio_out_pad[6]));
pc3o05 pc3o05_gpio_out7(.I (gpio_out[7]), .PAD (gpio_out_pad[7]));
pc3o05 pc3o05_gpio_out8(.I (gpio_out[8]), .PAD (gpio_out_pad[8]));
pc3o05 pc3o05_gpio_out9(.I (gpio_out[9]), .PAD (gpio_out_pad[9]));
pc3o05 pc3o05_flash_magic_word(.I (flash_magic_word), .PAD (flash_magic_word_pad));
pc3o05 pc3o05_pcpi_valid(.I (pcpi_valid), .PAD (pcpi_valid_pad));
pc3o05 pc3o05_pcpi_ready(.I (pcpi_ready), .PAD (pcpi_ready_pad));

pc3d01 pc3d01_clk(.PAD (clk_pad), .CIN (clk_intermediate));
pc3c01 pc3c01_clk_intermediate(.CCLK (clk_intermediate), .CP (clk));

`endif

//------------------------------------//
// Synchroniser Cycle Count Parameter //
//------------------------------------//
parameter REFRESH_CYCLES = 1_000_000; // Number of clock cycles for 10 ms at 100 MHz

//------------------------//
// Parameters for Flash   //
//------------------------//
parameter AW = 22; // Must match wbqspiflash: AW = ADDRESS_WIDTH - 2

//----------------------------//
// Parameters for Custom RTL  //
//----------------------------//
parameter W = 32; // Data width
parameter N = 14;

//---------------------------------------------------------------------------------------------//
//---------------------------------------------------------------------------------------------//
// Address Spaces Defined for each peripheral access and CSRS                                  //
//---------------------------------------------------------------------------------------------//
//---------------------------------------------------------------------------------------------//

//---------------------------------//
// BootROM Address Map and Start   //
//---------------------------------//
parameter BOOTROM_REG_START = 32'h0000_0000;
parameter BOOTROM_REG_END = 32'h0000_3FFC;

//-------------------------------------------------------//
// GPIO Memory Map and Start and Stop Sequence Counter   //
//-------------------------------------------------------//
parameter GPIO_OUT_ADDR = 32'h0500_0000; // GPIO output register base

// parameter CNT_START_ADDR = 32'h0400_0000; // Sequence start counter register
// parameter CNT_STOP_ADDR = 32'h0400_0004;  // Sequence stop/value counter register

//----------------------------------------------------//
// SPI flash Memory Map (0x0100_0000 to 0x01FF_FFFF)  //
// SPI CSR at 0x0010_0000 (SPI_CTRL_REG)              //
//----------------------------------------------------//
parameter SPI_ACCESS_REG_BASE=32'h0100_0000; // SPI flash data window start
parameter SPI_ACCESS_REG_END=32'h01FF_FFFF; // SPI flash data window end

parameter SPI_CTRL_REG=32'h0010_0000; // SPI control/status register

//-------------------------------------------------------------//
// UART Transreciever Memory Map (0x0300_0000 to 0x0300_00FF)  //
//-------------------------------------------------------------//
parameter UART_TRANSCEIVER_REG_BASE = 32'h0300_0000; // UART register window start
parameter UART_TRANSCEIVER_REG_END = 32'h0300_00FF; // UART register window end

//-----------------------------------------------//
// SRAM Memory Map (0x0600_0000 to 0x0600_3FFC)  //
//-----------------------------------------------//
parameter SRAM_REG_START = 32'h0600_0000; // SRAM window start
parameter SRAM_REG_END = 32'h0600_3FFC; // SRAM window end (4KB, 32-bit words)
parameter SRAM_CSR_BASE = 32'h0020_0000; // SRAM CSR register address

//----------------------//
// Synchronised signals //
//----------------------//
wire load_en;
wire [1:0] mode_sel;

//----------------------------------//
// Core native memory interface     //
//----------------------------------//
wire        resetn;
wire        core_resetn;
wire        mem_valid;
wire        mem_instr;
wire        mem_ready;
wire [31:0] mem_addr;
wire [31:0] mem_wdata;
wire [3:0]  mem_wstrb;
wire [31:0] mem_rdata;
//----------------------------------//
// PicoRV32 auxiliary ports        //
//----------------------------------//
wire [31:0] pcpi_insn;
wire [31:0] pcpi_rs1;
wire [31:0] pcpi_rs2;
wire        pcpi_wr;
wire [31:0] pcpi_rd;
wire        pcpi_wait;
wire [31:0] irq;
wire [31:0] eoi;
wire        trace_valid;
wire [35:0] trace_data;

//----------------------------------//
// Core look-ahead interface        //
//----------------------------------//
wire        mem_la_read;
wire        mem_la_write;
wire [31:0] mem_la_addr;
wire [31:0] mem_la_wdata;
wire [3:0]  mem_la_wstrb;

//----------------------------------//
// Core read-trace helper signals   //
//----------------------------------//
reg [31:0] m_read_data;
wire       m_read_en;

//----------------------------------//
// SRAM CSR interface signals       //
//----------------------------------//
wire        SRAM_CSR_VALID;
wire        SRAM_CSR_ready;
wire [31:0] CSR_rdata;

//----------------------------------//
// Custom RTL control/status        //
//----------------------------------//
wire        boot_en;
wire [31:0] FW_WDATA;
wire        core_decoder_en;
wire        core_decoder_en_remap;
wire        sync_core_resetn;
wire        load_done_core;
wire        load_busy_core;

//----------------------------------//
// SRAM decode path signals         //
//----------------------------------//
wire [31:0] SRAM_ADDR_RAW;
wire        fw_load_en;
wire [31:0] CORE_ADDR;

//----------------------------------//
// BootROM BRAM-side signals        //
//----------------------------------//
wire [31:0] bootrom_rdata;
wire        bootrom_valid;
wire        bootrom_ready;
wire        bootrom_wea;

//----------------------------------//
// SRAM BRAM-side signals           //
//----------------------------------//
wire [N-1:0] SRAM_ADDR;
wire [31:0]  SRAM_WDATA;
wire [31:0]  SRAM_RDATA;
wire         sram_valid;
wire         sram_ready;
wire         sram_wea;

//----------------------------------//
// UART loader to SRAM path         //
//----------------------------------//
wire sram_valid_uart;
wire sram_wea_uart;

//----------------------------------//
// Core to SRAM path                //
//----------------------------------//
wire sram_valid_core;
wire sram_wea_core;

//----------------------------------//
// GPIO output state                //
//----------------------------------//
wire [9:0] gpio_reg;

//----------------------------------//
// SPI bridge request path          //
//----------------------------------//
reg [23:0]  spi_adress;
wire        spi_mem_valid;
wire        addr_is_ctrl;
wire [31:0] flash_rdata;
wire [31:0] spi_cpu_mem_addr_latched;
wire        flash_ready;

//----------------------------------//
// Bridge to controller bus signals //
//----------------------------------//
wire           i_wb_cyc;
wire           i_wb_stb;
wire           i_wb_ctrl_stb;
wire           i_wb_we;
wire [AW-1:0]  i_wb_addr;
wire [31:0]    i_wb_wdata;

//----------------------------------//
// Controller to bridge bus signals //
//----------------------------------//
wire        o_wb_stall;
wire        o_wb_ack;
wire [31:0] o_wb_data;

//----------------------------------//
// QSPI internal data signals       //
//----------------------------------//
wire [1:0] o_qspi_mod;
wire [3:0] o_qspi_dat;
wire [3:0] i_qspi_dat;
wire oe_dat0;
wire oe_dat1;
wire oe_dat2;
wire oe_dat3;


//----------------------------------//
// UART transceiver interface       //
//----------------------------------//
wire        is_uart_access;
wire        uart_transceiver_valid;
wire        uart_transceiver_ready;
wire [31:0] uart_txrx_rdata;


//------------------------------//
// Reset Synchroniser Instance  //
//------------------------------//
reset_synch #(
        .FF_COUNT(FF_COUNT)
) u_reset_synch (
        .clk          (clk),
        .master_resetn(master_resetn),
        .resetn       (resetn)
);

//-----------------------//
// Synchroniser Instance //
//-----------------------//
synchroniser #(
        .REFRESH_CYCLES(REFRESH_CYCLES) // 10 ms at 100 MHz
) u_synchroniser (
        .clk          (clk),
        .resetn       (resetn),
        .load_en_async(load_en_asynch),
        .mode_sel_async(mode_sel_asynch),

        .load_en      (load_en),
        .mode_sel     (mode_sel)
);

//------------------------//
// PicoRV32 Core Instance //
//------------------------//
picorv32 #(
    .ENABLE_IRQ(1),
    .ENABLE_IRQ_TIMER(1),
    .LATCHED_IRQ(32'hfffffffe) // unlatch timer irq
) picorv32_core (
	.clk         (clk         ),
	.resetn      (core_resetn ),
	.trap        (trap        ),
	.mem_valid   (mem_valid   ),
	.mem_instr   (mem_instr   ),
	.mem_ready   (mem_ready   ),
	.mem_addr    (mem_addr    ),
	.mem_wdata   (mem_wdata   ),
	.mem_wstrb   (mem_wstrb   ),
	.mem_rdata   (mem_rdata   ),
	.mem_la_read (mem_la_read ),
	.mem_la_write(mem_la_write),
	.mem_la_addr (mem_la_addr ),
	.mem_la_wdata(mem_la_wdata),
        .mem_la_wstrb(mem_la_wstrb),
        .pcpi_valid  (pcpi_valid  ),
        .pcpi_insn   (pcpi_insn   ),
        .pcpi_rs1    (pcpi_rs1    ),
        .pcpi_rs2    (pcpi_rs2    ),
        .pcpi_wr     (pcpi_wr     ),
        .pcpi_rd     (pcpi_rd     ),
        .pcpi_wait   (pcpi_wait   ),
        .pcpi_ready  (pcpi_ready  ),
        .irq         (irq         ),
        .eoi         (eoi         ),
        .trace_valid (trace_valid ),
        .trace_data  (trace_data  )
);

//---------------------//
// core_decoder_remap  //
//---------------------//
core_bootrom_remap #(
        .BOOTROM_REG_START     (BOOTROM_REG_START),
        .BOOTROM_REG_END       (BOOTROM_REG_END)
) u_core_bootrom_remap (
        .mode_sel              (mode_sel),
        .mem_addr              (mem_addr),
        .mem_valid             (mem_valid),
        .core_decoder_en_remap (core_decoder_en_remap)
);

//----------------------//
// Custom RTL Instance  //
//----------------------//
SRAM_controller #(
        .W(W),
        .N(N)
) u_sram_ctrl (
        .clk              (clk),
        .resetn_in        (resetn),
        .load_en          (load_en),
        .i_rx             (FW_loader_UART_i_rx),
        .mode_sel         (mode_sel),

        // Signals from Core
        .load_done_core   (load_done_core), // To determine when boot loading is done
        .load_busy_core   (load_busy_core), // To determine when boot loading is in progress
        .CORE_ADDR        (mem_addr), // Address from core for decoding and determining if it's a load/store to SRAM
        .CORE_WDATA       (mem_wdata), // Data from core for store operations

        // Signals to Core
        .sync_core_resetn (sync_core_resetn), // Synchronous reset to core (active low)
        .boot_en          (boot_en),

        // Signals to address decoder
        .SRAM_ADDR_RAW    (SRAM_ADDR_RAW), // Address input from firmware loading path (could be from UART or FIFO loader)
        .fw_load_en       (fw_load_en), // Indicates if the firmware is being loaded

        //Signals to SRAM (after MUX selection)
        .SRAM_WDATA       (SRAM_WDATA), // Final write data to SRAM

        //Flags and Status outputs
        .load_busy        (load_busy),
        .load_done        (load_done),
        .o_rts            (FW_loader_UART_o_rts),
        .UART_check_start (FW_loader_UART_check_start),
        .UART_rx_error    (FW_loader_UART_rx_error),
        .header_fail      (FW_loader_UART_header_fail),

        //BRAM Specific signals
        .sram_valid_uart  (sram_valid_uart),
        .sram_wea_uart    (sram_wea_uart)
  );

addr_decoder #(
        .N(N)
) u_addr_decoder (
        .fw_load_en            (fw_load_en),
        .core_decoder_en       (core_decoder_en),
        .core_decoder_en_remap (core_decoder_en_remap),
        .mode_sel              (mode_sel),
        .SRAM_ADDR_RAW         (SRAM_ADDR_RAW),
        .SRAM_ADDR             (SRAM_ADDR)
);

//-----------------------------//
// BootROM Wrapper Instance   //
//-----------------------------//
Bootrom_wrapper u_bootrom_wrapper (
        .clk            (clk),
        .resetn         (resetn),
        .mem_addr       (mem_addr),
        .mem_wdata      (mem_wdata),
        .bootrom_wea    (bootrom_wea),
        .bootrom_valid  (bootrom_valid),
        .SRAM_CSR_Valid (SRAM_CSR_VALID),
        .mem_wstrb      (mem_wstrb),
        .boot_en        (boot_en),
        .CSR_rdata      (CSR_rdata),
        .SRAM_CSR_ready (SRAM_CSR_ready),
        .bootrom_rdata  (bootrom_rdata),
        .load_done_core (load_done_core),
        .load_busy_core (load_busy_core)
);

SRAM_wrapper #(
        .N(N)
) u_sram_wrapper (
        .clk        (clk),
        .resetn     (resetn),
        .sram_wea   (sram_wea),
        .SRAM_WDATA (SRAM_WDATA),
        .sram_valid (sram_valid),
        .SRAM_ADDR  (SRAM_ADDR),
        .SRAM_RDATA (SRAM_RDATA)
);

//--------------------------------//
// UART Transreceiver Instance   //
//--------------------------------//
soc_uart_subsystem  u_soc_uart_subsystem(
        // System Inputs
        .clk            (clk),
        .sync_core_resetn (sync_core_resetn),

        // RISC-V Native Memory Interface
        .mem_valid      (uart_transceiver_valid),
        //.mem_instr, // Ignored for UART (data access only)
        .mem_addr       (mem_addr),
        .mem_wdata      (mem_wdata),
        .mem_wstrb      (mem_wstrb),
        .mem_rdata      (uart_txrx_rdata),
        .mem_ready      (uart_transceiver_ready),
        .is_uart_access (is_uart_access),

        // External UART Pins (To Pads)
        .stx_pad_o      (CPU_UART_TRANSCEIVER_TX),
        .srx_pad_i      (CPU_UART_TRANSCEIVER_RX),
        .rts_pad_o      (CPU_RTS),
        .cts_pad_i      (CPU_CTS)
);

//-------------------------------//
// Pico --> Wishbone Instance    //
//-------------------------------//
mem_to_wb_bridge core_wb_bridge(
        // CPU side (core's native memory interface)
        .clk            (clk),
	.resetn         (resetn),
	.cpu_mem_valid  (spi_mem_valid),
	.cpu_mem_instr  (mem_instr),
	.cpu_mem_ready  (flash_ready),
        .cpu_mem_addr   (spi_cpu_mem_addr_latched),
	.cpu_mem_wdata  (mem_wdata),
	.cpu_mem_wstrb  (mem_wstrb),
	.cpu_mem_rdata_ (flash_rdata),

	//outputs to controller
	.i_wb_cyc       (i_wb_cyc),
        .i_wb_data_stb  (i_wb_stb),
        .i_wb_ctrl_stb  (i_wb_ctrl_stb),
        .i_wb_we        (i_wb_we),
        .i_wb_addr      (i_wb_addr),
        .i_wb_data      (i_wb_wdata),

        //inputs to bridge
        .o_wb_stall     (o_wb_stall),
        .o_wb_ack       (o_wb_ack),
        .o_wb_data      (o_wb_data),
        .addr_is_ctrl   (addr_is_ctrl)
);

//---------------------------------------//
// Controller (qflexpress.v) Instance    //
//---------------------------------------//
qflexpress_subsystem u_qflexpress_subsystem (
        .clk       (clk),
        .resetn    (resetn),
        .i_wb_cyc  (i_wb_cyc),
        .i_wb_stb  (i_wb_stb),
        .i_wb_ctrl_stb(i_wb_ctrl_stb),
        .i_wb_we   (i_wb_we),
        .i_wb_addr (i_wb_addr),
        .i_wb_wdata(i_wb_wdata),
        .o_wb_stall(o_wb_stall),
        .o_wb_ack  (o_wb_ack),
        .o_wb_data (o_wb_data),
        .o_qspi_sck(o_qspi_sck),
        .o_qspi_cs_n(o_qspi_cs_n),
        .flash_magic_word(flash_magic_word),
`ifdef FOR_ASIC
         .qspi_i (qspi_i),
         .qspi_o (qspi_o),
         .oe_dat_out (oe_dat_out)
`else
        .qspi_io_3 (qspi_io_3),
        .qspi_io_2 (qspi_io_2),
        .qspi_io_1 (qspi_io_1),
        .qspi_io_0 (qspi_io_0)
`endif
 );


//-------------------------------------//
// GPIO Display Logic Instance         //
//-------------------------------------//
gpio_display_logic u_gpio_display_logic (
        .clk          (clk),
        .resetn       (resetn),
        .gpio_reg     (gpio_reg),
        .gpio_out     (gpio_out)
);

//-------------------------------------//
// SRAM/BootROM Ready Logic Instance   //
//-------------------------------------//
sram_bootrom_ready_logic #(
        .BOOTROM_REG_START(BOOTROM_REG_START),
        .BOOTROM_REG_END  (BOOTROM_REG_END)
) u_sram_bootrom_ready_logic (
        .clk             (clk),
        .resetn          (resetn),
        .mem_valid       (mem_valid),
        .mode_sel        (mode_sel),
        .mem_addr        (mem_addr),
        .sram_valid_core (sram_valid_core),
        .sram_wea_core   (sram_wea_core),
        .sram_wea_uart   (sram_wea_uart),
        .sram_valid_uart (sram_valid_uart),
        .bootrom_valid   (bootrom_valid),
        .bootrom_ready   (bootrom_ready),
        .sram_ready      (sram_ready),
        .sram_wea        (sram_wea),
        .sram_valid      (sram_valid)
);

//-------------------------------------//
// Core Intermediate Logic Instance    //
//-------------------------------------//
core_intermediate #(
        .SRAM_REG_START(SRAM_REG_START),
        .SRAM_REG_END  (SRAM_REG_END)
) u_core_intermediate (
        .sync_core_resetn (sync_core_resetn),
        .mem_valid        (mem_valid),
        .mem_addr         (mem_addr),
        .pcpi_wr          (pcpi_wr),
        .pcpi_rd          (pcpi_rd),
        .pcpi_wait        (pcpi_wait),
        .pcpi_ready       (pcpi_ready),
        .irq              (irq),
        .eoi              (eoi),
        .trace_valid      (trace_valid),
        .trace_data       (trace_data),
        .core_resetn      (core_resetn),
        .core_decoder_en  (core_decoder_en)
);
//-------------------------------------//
// Core Address Forward Logic Instance //
//-------------------------------------//
core_addr_forward #(
        .GPIO_OUT_ADDR             (GPIO_OUT_ADDR),
        .SPI_ACCESS_REG_BASE       (SPI_ACCESS_REG_BASE),
        .SPI_ACCESS_REG_END        (SPI_ACCESS_REG_END),
        .SPI_CTRL_REG              (SPI_CTRL_REG),
        .UART_TRANSCEIVER_REG_BASE (UART_TRANSCEIVER_REG_BASE),
        .UART_TRANSCEIVER_REG_END  (UART_TRANSCEIVER_REG_END),
        .SRAM_REG_START            (SRAM_REG_START),
        .SRAM_REG_END              (SRAM_REG_END),
        .SRAM_CSR_BASE             (SRAM_CSR_BASE)
) u_core_addr_forward (
        .clk                      (clk),
        .resetn                   (resetn),
        .mem_instr                (mem_instr),
        .mem_valid                (mem_valid),
        .mem_addr                 (mem_addr),
        .mem_wdata                (mem_wdata),
        .mem_wstrb                (mem_wstrb),
        .core_decoder_en_remap    (core_decoder_en_remap),
        .flash_ready              (flash_ready),
        .flash_rdata              (flash_rdata),
        .uart_transceiver_ready   (uart_transceiver_ready),
        .uart_txrx_rdata          (uart_txrx_rdata),
        .sram_ready               (sram_ready),
        .SRAM_RDATA               (SRAM_RDATA),
        .bootrom_valid            (bootrom_valid),
        .bootrom_ready            (bootrom_ready),
        .bootrom_rdata            (bootrom_rdata),
        .SRAM_CSR_ready           (SRAM_CSR_ready),
        .CSR_rdata                (CSR_rdata),
        .gpio_reg                 (gpio_reg),
        .m_read_en                (m_read_en),
        .bootrom_wea              (bootrom_wea),
        .sram_valid_core          (sram_valid_core),
        .sram_wea_core            (sram_wea_core),
        .SRAM_CSR_VALID           (SRAM_CSR_VALID),
        .spi_mem_valid            (spi_mem_valid),
        .addr_is_ctrl             (addr_is_ctrl),
        .spi_cpu_mem_addr_latched (spi_cpu_mem_addr_latched),
        .is_uart_access           (is_uart_access),
        .uart_transceiver_valid   (uart_transceiver_valid),
        .mem_ready                (mem_ready),
        .mem_rdata                (mem_rdata)
);

`ifdef FOR_FPGA_BOARD
        //-------------------//
        // Startup Primitive //
        //-------------------//
    STARTUPE2 STARTUPE2_inst (
        .CFGCLK(),
        .CFGMCLK(),
        .EOS(),
        .PREQ(),

        .CLK(1'b0),
        .GSR(1'b0),
        .GTS(1'b0),
        .KEYCLEARB(1'b1),
        .PACK(1'b1),

        .USRCCLKO(o_qspi_sck),  ////User defined spi_clock
        .USRCCLKTS(1'b0),

        .USRDONEO(1'b1),
        .USRDONETS(1'b1)
    );
`endif

endmodule
