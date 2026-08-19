`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Shashank Tiwari, Samyak Nidhi
// Module Name: tb_uart_firmware_dynamic(SOC_V1.1)
// Description:
// Minimal Testbench for UART backup path using dynamic $readmemh loading
// complete bootrom + firmware into sram.
// mode_sel = 2'b10 (UART backup mode)
//////////////////////////////////////////////////////////////////////////////////

`include "global_defines.v"

module tb_uart_with_firmware;

    reg clk = 1'b1;
    always #5 clk = ~clk; // 100 MHz clock

    wire resetn;
    reg load_en  = 1'b0;
    reg [1:0] mode_sel = 2'b10;
    reg i_rx_tb = 1'b1;

    localparam [1:0] UART_MODE_SEL = 2'b10;
    localparam integer CLK_FREQ_HZ = 100_000_000;
    localparam integer UART_LOAD_BAUD = 115200; // High baud for faster test, but still within receiver model limits.

    localparam integer UART_CLKS_PER_BIT = (CLK_FREQ_HZ / UART_LOAD_BAUD);

    wire trap;
    wire uart_tx;
    wire [7:0] recv_data;
    wire data_valid_rcv;
    wire [9:0] gpio_out;
    wire load_busy, load_done;
    wire o_rts, UART_rx_error, UART_check_start;
    wire SCK, CS_N;
    wire IO_data_3, IO_data_2, IO_data_1, IO_data_0;
    wire flash_magic_word;
    reg [15:0] current_word;
    wire header_fail; // newly added port
    wire CPU_CTS = 1'b0;
    wire CPU_RTS;
    wire pcpi_valid;
    wire pcpi_ready;

    reg master_resetn = 1'b0;
    integer wait_cycles = 0;

    // -------------------------------------------------------------------------
    // DYNAMIC PAYLOAD MEMORY
    // -------------------------------------------------------------------------
    reg [31:0] uart_payload_mem [0:4095]; // Can hold up to 4096 words

    `ifdef CADENCE_GLS
    initial begin
        // Inject the UART payload directly into the testbench array
        $readmemh("../memh_files/full_fw_uart_path.memh", uart_payload_mem);
        $display("TB_NOTE: UART payload dynamically loaded from .memh file!");
    end
    `else
    initial begin
        // Inject the UART payload directly into the testbench array
        $readmemh("full_fw_uart_path.memh", uart_payload_mem);
        $display("TB_NOTE: UART payload dynamically loaded from .memh file!");
    end
    `endif

    // -------------------------------------------------------------------------
    // SYSTEM INSTANTIATION
    // -------------------------------------------------------------------------

    system uut (
        .clk                        (clk),
        .master_resetn              (master_resetn),
        .trap                       (trap),
        .gpio_out                   (gpio_out),
        .load_en_asynch             (load_en),           // mapped to new port (synchronized)
        .FW_loader_UART_i_rx        (i_rx_tb),           // mapped to new port
        .mode_sel_asynch            (mode_sel),          // mapped to new port (synchronized)
        .load_busy                  (load_busy),
        .load_done                  (load_done),
        .FW_loader_UART_o_rts       (o_rts),             // mapped to new port
        .FW_loader_UART_rx_error    (UART_rx_error),     // mapped to new port
        .FW_loader_UART_check_start (UART_check_start),  // mapped to new port
        .o_qspi_sck                 (SCK),
        .o_qspi_cs_n                (CS_N),
        .qspi_io_3                  (IO_data_3),
        .qspi_io_2                  (IO_data_2),
        .qspi_io_1                  (IO_data_1),
        .qspi_io_0                  (IO_data_0),
        .flash_magic_word           (flash_magic_word),
        .CPU_UART_TRANSCEIVER_TX    (uart_tx),           // mapped to new port
        .CPU_UART_TRANSCEIVER_RX    (1'b1),              // mapped to new port
        .CPU_RTS                    (CPU_RTS),           // mapped to new port
        .CPU_CTS                    (CPU_CTS),
        .pcpi_valid                 (pcpi_valid),        // mapped to new port
        .pcpi_ready                 (pcpi_ready),        // mapped to new port
        .FW_loader_UART_header_fail (header_fail)        // newly added port
    );

    uart_rx_sim u_uart_rx_mon (
        .clk(clk),
        .resetn(resetn),
        .rx(uart_tx),
        .data_out(recv_data),
        .data_valid(data_valid_rcv)
    );

    always @(posedge clk) begin
        if (data_valid_rcv)
            $display("UART TX: 0x%02h", recv_data);
    end

    // Keep flash model connected to avoid floating pins
    W25Q16JV flash_mem (
        .CSn   (CS_N),
        .CLK   (SCK),
        .DIO   (IO_data_0),
        .DO    (IO_data_1),
        .WPn   (IO_data_2),
        .HOLDn (IO_data_3)
    );

    // -------------------------------------------------------------------------
    // UART TRANSMISSION TASKS
    // -------------------------------------------------------------------------
    function [31:0] uart_word_at;
        input integer idx;
        begin
            uart_word_at = uart_payload_mem[idx];
        end
    endfunction

    task automatic uart_wait_bit;
    begin
        repeat (UART_CLKS_PER_BIT) @(posedge clk);
    end
    endtask

    task automatic uart_send_byte;
            input [7:0] b;
            integer i;
        begin
            i_rx_tb = 1'b0; // Start bit
            uart_wait_bit();

            for (i = 0; i < 8; i = i + 1) begin
                i_rx_tb = b[i]; // Data bits
                uart_wait_bit();
            end

            i_rx_tb = 1'b1; // Stop bit
            uart_wait_bit();

            // --- THE FIX: Clear Cumulative Drift ---
            // Hold the line IDLE for one extra bit period.
            // This guarantees the RTL receiver finishes its state
            // transition and is ready for the next clean Start bit.
            uart_wait_bit();
        end
        endtask

    task automatic uart_send_word;
        input [31:0] w;
    begin
        uart_send_byte(w[31:24]);
        uart_send_byte(w[23:16]);
        uart_send_byte(w[15:8]);
        uart_send_byte(w[7:0]);
    end
    endtask

    task automatic uart_wait_rts_high;
        input integer max_cycles;
        integer c;
    begin
        c = 0;
        while (o_rts !== 1'b1 && c < max_cycles) begin
            @(posedge clk);
            c = c + 1;
        end
    end
    endtask

    task automatic uart_send_word_cts;
        input [31:0] w;
    begin
        uart_wait_rts_high(500000);
        uart_send_word(w);
    end
    endtask

    task automatic send_uart_payload;
        integer wi;
        integer payload_n_words;
        integer total_words;
        reg [31:0] first_word;
    begin
        // Use below code if header is not part of memh file.
        // Second part of header is no. of words in payload.
        //header_word = {16'hA5D5, 16'd2668};
        //uart_send_word_cts(header_word);

        first_word = uart_word_at(0);
        payload_n_words = first_word[15:0];
        total_words = payload_n_words + 1; // header (1 word) + payload

        if (total_words > 4096) begin
            $display("TB_ERROR: Header payload length %0d exceeds uart_payload_mem depth.", payload_n_words);
            $finish;
        end

        for (wi = 0; wi < total_words; wi = wi + 1) begin
            uart_send_word_cts(uart_word_at(wi));
            current_word = wi;
        end
    end
    endtask

`ifdef FOR_ASIC
initial
begin
	$sdf_annotate("../GLS/constraints.sdf", uut, "", "sdf_uart_timing.log", "MAXIMUM");
end
`endif

    // -------------------------------------------------------------------------
    // MAIN TEST SEQUENCE
    // -------------------------------------------------------------------------
    initial begin
        #1;
        master_resetn = 1'b0;
        load_en = 1'b0;
        mode_sel = UART_MODE_SEL;
        i_rx_tb = 1'b1;

        // Apply reset
        repeat (20) @(posedge clk);
        #1;
        master_resetn = 1'b1;

        // Wait for synchronized reset release, then allow extra settle cycles
        wait (uut.resetn === 1'b1);
        #1;
        repeat (16) @(posedge clk);

        $display("TB mode: UART backup to SRAM load.");

        // Kick UART backup load
        @(posedge clk);
        #1;
        load_en = 1'b1;
        repeat (5) @(posedge clk); // Pulse widened for synchroniser capture
        load_en = 1'b0;

        // Send header + payload while core is in reset
        send_uart_payload();

        // Wait until firmware load completes
        while (!load_done) begin
            #1;
            @(posedge clk);
        end

        $display("Firmware load via UART completed successfully.");

        `ifndef CADENCE_GLS
        $finish; // can manually continue execution from here to see execution
        `endif
    end

endmodule