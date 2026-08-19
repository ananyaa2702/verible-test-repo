`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Rohith Suju
// Create Date: 07.07.2026
// Module Name: tb_uart_flow_ctrl_fw
// Project Name: SoC KNN
// Description:
// Testbench to verify UART flow control functionality of the CPU UART Subsystem.
// Tests both RTS and CTS signaling, ensuring proper handshaking during UART data
// transmission.
//////////////////////////////////////////////////////////////////////////////////

`include "global_defines.v"

`define FAST_LOAD

module tb_uart_flow_ctrl_fw;

    reg clk = 1'b1;
    always #5 clk = ~clk;

    wire resetn ;
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
    reg CPU_CTS = 1'b0;
    reg CPU_RTS;
    wire pcpi_valid;
    wire pcpi_ready;

    reg master_resetn = 1'b0;
    wire [9:0] gpio_out;

    integer wait_cycles;

    // Keep RX idle high; this TB only monitors DUT UART TX.
    assign uart_rx = 1'b1;

    uart_rx_sim u_uart_rx_mon (
        .clk(clk),
        .resetn(resetn),
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


     W25Q16JV flash_mem (
            .CSn   (CS_N),
            .CLK   (SCK),
            .DIO   (IO_data_0),
            .DO    (IO_data_1),
            .WPn   (IO_data_2),
            .HOLDn (IO_data_3)
     );



`ifndef BEHAV_BOOTROM
`ifdef FAST_LOAD
   initial begin
        // Wait a brief moment for the IP's internal logic to settle
        #1;
             // Inject the new firmware directly into the simulation array change this for fast bootrom loading
        $readmemh("bootrom_uart_flow_ctrl.memh",
                  uut.u_bootrom_wrapper.bootrom.inst.native_mem_module.blk_mem_gen_v8_4_9_inst .memory);
             $display("TB_NOTE: Fast-loaded custom firmware into BootROM bypassing synthesis!");
   end
`endif
`endif

   always @(posedge clk) begin
        if (data_valid_rcv)
        $display("UART TX: 0x%02h", recv_data);
   end

   initial begin
    //resetn   = 1'b0;
    load_en  = 1'b0;
    mode_sel = FLASH_MODE_SEL;

    repeat (20) @(posedge clk);
    master_resetn = 1'b1;
    // Wait for synchronized reset release, then allow extra settle cycles.
    repeat (20) @(posedge clk);

    $display("UART RTS/CTS test");

    // Start the core
    @(posedge clk); load_en = 1'b1; // then enabling core
    repeat (5) @(posedge clk); // Ensure pulse is wide enough for async synchronizer
    load_en = 1'b0;

    CPU_CTS = 0;
    $display("CTS low");
    #100000
    CPU_CTS = 1;
    $display("CTS high");
    #1000000
    CPU_CTS = 0;
    $display("CTS low");
    #1000000;
    $finish;
   end

endmodule

