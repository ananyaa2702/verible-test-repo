`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Shashank Tiwari, Samyak Nidhi
// Module Name: tb_flash_with_firmware(SOC_V1.1)
// Description:
// Testbench for flash -> SRAM loading of verified firmware (soc_1.0) and execution
//////////////////////////////////////////////////////////////////////////////////

`include "global_defines.v"

`define FAST_LOAD

`define SPANSION_FLASH_MODEL
    // `define BASYS_3
    `define ARTY_A7

module tb_flash_with_firmware;

    reg clk = 1'b1;
    always #5 clk = ~clk;
    reg load_en  = 1'b0;
    reg [1:0] mode_sel = 2'b00;
    reg i_rx_tb = 1'b1;

    localparam [1:0] FLASH_MODE_SEL = 2'b00;

    wire uart_tx;
    wire uart_rx;
    wire [7:0] recv_data;
    wire data_valid_rcv;
    wire trap;

    //wire uart_tx_busy, uart_txd;
    wire [4:0] outp_idx;
    wire [3:0] outp_label;
    wire load_busy, load_done;
    wire o_rts, UART_rx_error, UART_check_start;
    wire SCK, CS_N;
    wire IO_data_3, IO_data_2, IO_data_1, IO_data_0;
    wire header_fail; // newly added port
    wire flash_magic_word; // magic_word match
    wire CPU_CTS = 1'b0;
    wire CPU_RTS;
    wire pcpi_valid;
    wire pcpi_ready;

    reg master_resetn = 1'b0;
    wire [9:0] gpio_out;

    integer wait_cycles;

    // Keep RX idle high; this TB only monitors DUT UART TX.
    assign uart_rx = 1'b1;

    uart_rx_sim u_uart_rx_mon (
        .clk(clk),
        .resetn(master_resetn),
        .rx(uart_tx),
        .data_out(recv_data),
        .data_valid(data_valid_rcv)
    );

    system uut (
        .clk                        (clk),
        .master_resetn              (master_resetn),
        .trap                       (trap),
        .gpio_out                   (gpio_out),
        .load_en_asynch             (load_en),           // mapped to asynch port
        .FW_loader_UART_i_rx        (i_rx_tb),
        .mode_sel_asynch            (mode_sel),          // mapped to asynch port
        .load_busy                  (load_busy),
        .load_done                  (load_done),
        .FW_loader_UART_o_rts       (o_rts),
        .FW_loader_UART_rx_error    (UART_rx_error),
        .FW_loader_UART_check_start (UART_check_start),
        .o_qspi_sck                 (SCK),
        .o_qspi_cs_n                (CS_N),
        .flash_magic_word           (flash_magic_word),
        .qspi_io_3                  (IO_data_3),
        .qspi_io_2                  (IO_data_2),
        .qspi_io_1                  (IO_data_1),
        .qspi_io_0                  (IO_data_0),
        .CPU_UART_TRANSCEIVER_TX    (uart_tx),
        .CPU_UART_TRANSCEIVER_RX    (uart_rx),
        .CPU_CTS                    (CPU_CTS),              // mapped to new port
        .CPU_RTS                    (CPU_RTS),           // mapped to new port
        .pcpi_valid                 (pcpi_valid),        // mapped to new port
        .pcpi_ready                 (pcpi_ready),        // mapped to new port
        .FW_loader_UART_header_fail (header_fail)
    );

    always @(posedge clk) begin
        if (data_valid_rcv)
        $display("UART TX: 0x%02h", recv_data);
    end

`ifdef SPANSION_FLASH_MODEL
	`ifdef ARTY_A7
	// Arty A7 flash
     	s25fl128s flash_mem_arty_a7 (
       		.SCK(SCK),
       		.CSNeg(CS_N),
       		.RSTNeg(master_resetn),
       		.SI(IO_data_0),
       		.SO(IO_data_1),
       		.WPNeg(IO_data_2),
       		.HOLDNeg(IO_data_3)
     	);
	`endif
	`ifdef BASYS_3
	// Basys 3 Flash
    	s25fl032p flash_mem_basys_3 (
      		.SCK(SCK),
      		.CSNeg(CS_N),
      		.SI(IO_data_0),
      		.SO(IO_data_1),
      		.WPNeg(IO_data_2),
      		.HOLDNeg(IO_data_3)
    	);
	`endif
`else
 W25Q16JV flash_mem (
        .CSn   (CS_N),
        .CLK   (SCK),
        .DIO   (IO_data_0),
        .DO    (IO_data_1),
        .WPn   (IO_data_2),
        .HOLDn (IO_data_3)
 );
`endif

reg        qspi_oe;      // 1: drive lines (write from flash), 0: release (read from flash)
reg [3:0]  qspi_out;     // bits to drive on IO[3:0]
wire [3:0] qspi_in;      // bits read from IO[3:0]

`ifndef BEHAV_BOOTROM
`ifdef FAST_LOAD
  initial begin
       // Wait a brief moment for the IP's internal logic to settle
       #1;
            // Inject the new firmware directly into the simulation array change this for fast bootrom loading
       $readmemh("bootrom_flash_path.memh",
                 uut.u_bootrom_wrapper.bootrom.inst.native_mem_module.blk_mem_gen_v8_4_12_inst .memory);
            $display("TB_NOTE: Fast-loaded custom firmware into BootROM bypassing synthesis!");
  end
`endif
`endif

`ifdef FOR_ASIC
initial
begin
	$sdf_annotate("../GLS/constraints.sdf", uut, "", "sdf_flash_timing.log", "MAXIMUM");
end
`endif

   initial begin
    load_en  = 1'b0;
    mode_sel = FLASH_MODE_SEL;
    qspi_oe  = 1'b0;
    qspi_out = 4'h0;

    repeat (20) @(posedge clk);
    master_resetn = 1'b1;
    // Wait for synchronized reset release, then allow extra settle cycles.
    repeat (20) @(posedge clk);
    #1;

    // Allow flash model startup before issuing reads.
    repeat (35000) @(posedge clk);

`ifdef SPANSION_FLASH_MODEL
    #100 // modified tdevice_PU (power up time) inside flash model to 100 for sim
`endif

    $display("TB mode: flash to SRAM load only.");

    // Trigger boot controller flash load path.
    @(posedge clk); load_en = 1'b1; // then enabling core
    repeat (5) @(posedge clk); // Ensure pulse is wide enough for async synchronizer
    #1;
    load_en = 1'b0;

    // No timeout: wait until firmware load completes.
    while (!load_done) begin
        @(posedge clk);
    end

    $display("Firmware load completed successfully.");

`ifndef CADENCE_GLS
    $finish;
`endif
   end

endmodule
