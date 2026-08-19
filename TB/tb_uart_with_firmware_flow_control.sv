`timescale 1ns / 1ps
///////////////////////////////////////////////////////////////////////////////////////////////////
// Engineer: Shashank Tiwari, Samyak Nidhi
// Update Date: 03.06.2026
// Module Name: tb_uart_with_firmware_flow_control
// Project Name: Silicon SoC kNN
//
// Description:
// Testbench for full firmware loading through the UART firmware loader while
// intentionally exercising RTS/CTS hardware flow control.
//
// Test Order:
// (1) Apply system reset and initialize UART firmware payload memory.
// (2) Build an SRAM write scoreboard from the firmware image to verify every
//     payload word written by the loader.
// (3) Trigger UART firmware loading and stream the complete firmware image
//     using CTS-aware UART transmit tasks.
// (4) Stall #1 at 500 transmitted words and verify FIFO backpressure through
//     RTS deassertion and clean recovery.
// (5) Stall #2 at 1500 transmitted words and verify FIFO backpressure through
//     RTS deassertion and clean recovery.
// (6) Continue transmission until the complete firmware image is sent.
// (7) Wait for load_done to confirm successful firmware loading.
// (8) Stop simulation using $finish so firmware execution can be manually
//     continued from the simulator GUI.
//
// Verification Features:
// - Dynamic firmware loading from .memh file.
// - RTS/CTS flow-control verification.
// - SRAM write scoreboard synchronized to SRAM write-enable.
// - Address and data integrity checking.
// - Firmware UART TX monitor.
// - Intentional FIFO backpressure testing.
// - Detection of dropped, corrupted, duplicated, or mis-addressed writes.
///////////////////////////////////////////////////////////////////////////////////////////////////

// Probe the actual SRAM Wrapper to ensure we only capture valid writes
`define PROBE_SRAM_WEA   uut.u_sram_wrapper.sram_wea
`define PROBE_SRAM_ADDR  uut.u_sram_wrapper.SRAM_ADDR
`define PROBE_SRAM_WDATA uut.u_sram_wrapper.SRAM_WDATA

// Path to trick the SRAM loader into pausing
`define PROBE_UART_RD_EN uut.u_sram_ctrl.u_uart_loader_subsystem.UART_rd_en

module tb_uart_with_firmware_flow_control;
    reg clk = 1'b1;
    always #5 clk = ~clk; // 25 MHz clock

    wire resetn;
    reg load_en  = 1'b0;
    reg [1:0] mode_sel = 2'b10;
    reg i_rx_tb = 1'b1;

    localparam [1:0] UART_MODE_SEL = 2'b10;
    localparam integer CLK_FREQ_HZ = 25_000_000;
    localparam integer UART_LOAD_BAUD = 1_000_000;
    localparam integer UART_CLKS_PER_BIT = (CLK_FREQ_HZ / UART_LOAD_BAUD);
    // Align loader RX timing model with this TB's parameters.
    defparam uut.u_sram_ctrl.u_uart_loader_subsystem.u_uart_rx_subsystem.uart_rx_fifo_u.SystemClockFreq = CLK_FREQ_HZ;
    defparam uut.u_sram_ctrl.u_uart_loader_subsystem.u_uart_rx_subsystem.uart_rx_fifo_u.BaudRate = UART_LOAD_BAUD;

    wire trap;
    wire uart_tx;
    wire [9:0] gpio_out;

    wire load_busy, load_done;
    wire o_rts, UART_rx_error, UART_check_start;
    wire SCK, CS_N;
    wire IO_data_3, IO_data_2, IO_data_1, IO_data_0;
    wire flash_magic_word;
    wire header_fail; // newly added port

    reg master_resetn = 1'b0;

    reg sender_done = 1'b0;
    integer words_sent = 0;
    integer errors = 0;
    integer words_written = 0;
    wire CPU_CTS = 1'b0;
    wire CPU_RTS;
    wire pcpi_valid;
    wire pcpi_ready;


    // -------------------------------------------------------------------------
    // DYNAMIC PAYLOAD MEMORY & SCOREBOARD
    // -------------------------------------------------------------------------
    reg [31:0] uart_payload_mem [0:4095];
    logic [31:0] expected_data_q[$];
    logic [31:0] expected_addr_q[$];

    initial begin
        $readmemh("full_fw_uart_path.memh", uart_payload_mem);
        $display("[%0t] TB_NOTE: UART payload dynamically loaded from .memh file!", $time);
    end

    // -------------------------------------------------------------------------
    // FIX: Removed reset_synch for post-synth compatibility and tied the wire directly
    // -------------------------------------------------------------------------
    assign resetn = master_resetn;

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
        .CPU_CTS                    (CPU_CTS),           // mapped to new port
        .CPU_RTS                    (CPU_RTS),           // mapped to new port
        .pcpi_valid                 (pcpi_valid),        // mapped to new port
        .pcpi_ready                 (pcpi_ready),        // mapped to new port
        .FW_loader_UART_header_fail (header_fail)        // newly added port
    );

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
    // FIRMWARE UART TX MONITOR (Self-Contained)
    // -------------------------------------------------------------------------
    // Listens to the PicoRV32's UART TX line without needing external modules
    localparam integer FW_BAUD_RATE = 115200;
    // Standard firmware baud rate
    localparam time FW_BIT_TIME_NS = 1_000_000_000 / FW_BAUD_RATE;
    reg [7:0] captured_byte;

    initial begin
        wait(resetn === 1'b1);
        // Wait for master reset release
        #(1000);

        forever begin
            @(negedge uart_tx);
            // Wait for Start Bit
            if (uart_tx === 1'b0) begin
                #(FW_BIT_TIME_NS / 2);
                // Sample at center of start bit
                if (uart_tx === 1'b0) begin
                    for (int i = 0; i < 8; i = i + 1) begin
                        #(FW_BIT_TIME_NS);
                        captured_byte[i] = uart_tx;
                    end
                    #(FW_BIT_TIME_NS);
                    // Wait for Stop bit
                    $display("[%0t] FIRMWARE UART TX: (0x%02h)", $time, captured_byte, captured_byte);
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // -------------------------------------------------------------------------
    initial begin
        $monitor("[%0t] HW MONITOR: o_rts is now %b", $time, o_rts);
    end

    // -------------------------------------------------------------------------
    // SRAM SCOREBOARD CHECKER (Synchronized directly to SRAM WEA)
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (resetn && load_busy) begin
            // ONLY check data exactly when the SRAM Wrapper is told to write
            if (`PROBE_SRAM_WEA === 1'b1) begin

                if (expected_data_q.size() > 0) begin
                    logic [31:0] exp_data = expected_data_q.pop_front();
                    logic [31:0] exp_addr = expected_addr_q.pop_front();

                    if (`PROBE_SRAM_ADDR !== exp_addr) begin
                        $error("[%0t] ERROR! SRAM ADDR Mismatch: Got 0x%08h, Expected 0x%08h", $time, `PROBE_SRAM_ADDR, exp_addr);
                        errors++;
                    end
                    if (`PROBE_SRAM_WDATA !== exp_data) begin
                        $error("[%0t] ERROR! SRAM DATA Mismatch at ADDR 0x%08h: Got 0x%08h, Expected 0x%08h", $time, `PROBE_SRAM_ADDR, `PROBE_SRAM_WDATA, exp_data);
                        errors++;
                    end
                    words_written++;
                end else begin
                    $error("[%0t] Unexpected SRAM Write (Scoreboard empty): ADDR=0x%08h DATA=0x%08h", $time, `PROBE_SRAM_ADDR, `PROBE_SRAM_WDATA);
                    errors++;
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // UART TRANSMISSION TASKS (With rigorous byte-level CTS checks)
    // -------------------------------------------------------------------------
    task automatic uart_wait_bit;
        begin
            repeat (UART_CLKS_PER_BIT) @(posedge clk);
        end
    endtask

    task automatic uart_send_byte_cts;
        input [7:0] b;
        integer i;
        begin
            // ---- THE FLOW CONTROL GATE ----
            if (o_rts !== 1'b1) begin
                $display("[%0t] SENDER PAUSED: Waiting for CTS (o_rts=1) to resume...", $time);
                while (o_rts !== 1'b1) @(posedge clk);
                $display("[%0t] SENDER RESUMED: CTS detected high. Sending next byte.", $time);
            end

            i_rx_tb = 1'b0;
            // Start bit
            uart_wait_bit();
            for (i = 0; i < 8; i = i + 1) begin
                i_rx_tb = b[i];
                // Data bits
                uart_wait_bit();
            end

            i_rx_tb = 1'b1;
            // Stop bit
            uart_wait_bit();
            uart_wait_bit();
            // Extra idle bit to clear cumulative drift
        end
    endtask

    task automatic uart_send_word_cts;
        input [31:0] w;
        begin
            uart_send_byte_cts(w[31:24]);
            uart_send_byte_cts(w[23:16]);
            uart_send_byte_cts(w[15:8]);
            uart_send_byte_cts(w[7:0]);
        end
    endtask

    task automatic send_uart_payload;
        integer wi;
        integer payload_n_words;
        integer total_words;
        reg [31:0] first_word;
        begin
            first_word = uart_payload_mem[0];
            payload_n_words = first_word[15:0];
            total_words = payload_n_words + 1; // header (1 word) + payload

            for (wi = 0; wi < total_words; wi = wi + 1) begin
                uart_send_word_cts(uart_payload_mem[wi]);
                words_sent = wi + 1;
            end
        end
    endtask

    // -------------------------------------------------------------------------
    // MAIN TEST SEQUENCE
    // -------------------------------------------------------------------------
    initial begin
        master_resetn = 1'b0;
        load_en = 1'b0;
        mode_sel = UART_MODE_SEL;
        i_rx_tb = 1'b1;
        sender_done = 1'b0;
        words_sent = 0;
        // Apply reset
        repeat (20) @(posedge clk);
        master_resetn = 1'b1;
        wait (resetn === 1'b1);
        repeat (16) @(posedge clk);

        // Prep the verification scoreboard
        begin
            int payload_sz = uart_payload_mem[0][15:0];
            for (int k = 1; k <= payload_sz; k++) begin
                expected_data_q.push_back(uart_payload_mem[k]);
                expected_addr_q.push_back((k - 1));
            end
            $display("[%0t] SCOREBOARD: Tracking %0d expected SRAM writes", $time, payload_sz);
        end

        $display("\n=========================================================================");
        $display("[%0t] TEST START: Dynamic RTS/CTS Verification mid-firmware", $time);
        $display("=========================================================================\n");
        // Give the SRAM loader its start pulse
        @(posedge clk) load_en = 1'b1;
        repeat (5) @(posedge clk); // Pulse widened for synchroniser capture
        @(posedge clk) load_en = 1'b0;
        // Start firmware pushing in parallel
        fork
            begin
                send_uart_payload();
                sender_done = 1'b1;
            end
        join_none

        // ---------------- STALL 1 (Location 1) ----------------
        wait(words_sent == 500);
        $display("\n============================================================");
        $display("[%0t] INITIATING INTENTIONAL STALL #1 (at %0d words sent)", $time, words_sent);
        $display("    Action: Forcing UART_rd_en = 0 to safely freeze accumulator.");
        $display("============================================================");

        force `PROBE_UART_RD_EN = 1'b0;
        wait (o_rts === 1'b0);
        $display("[%0t] VERIFIED: FIFO filled up. o_rts organically dropped to 0.", $time);
        $display("[%0t] WAITING: Simulating heavy stall period for 100,000 ns...", $time);
        repeat(10_000) @(posedge clk);

        $display("[%0t] RESUMING: Releasing accumulator read datapath.", $time);
        release `PROBE_UART_RD_EN;

        // ---------------- STALL 2 (Location 2) ----------------
        wait(words_sent == 1500);
        $display("\n============================================================");
        $display("[%0t] INITIATING INTENTIONAL STALL #2 (at %0d words sent)", $time, words_sent);
        $display("    Action: Forcing UART_rd_en = 0 to safely freeze accumulator.");
        $display("============================================================");

        force `PROBE_UART_RD_EN = 1'b0;
        wait (o_rts === 1'b0);
        $display("[%0t] VERIFIED: FIFO filled up. o_rts organically dropped to 0.", $time);
        $display("[%0t] WAITING: Delaying to test buffer integrity...", $time);
        repeat(8_000) @(posedge clk);

        $display("[%0t] RESUMING: Releasing accumulator read datapath.", $time);
        release `PROBE_UART_RD_EN;
        // ---------------- COMPLETION ----------------
        wait (sender_done);
        $display("\n[%0t] Sender thread successfully pushed all bytes to UART.", $time);
        while (!load_done) begin
            @(posedge clk);
        end
        $display("[%0t] Firmware loading signaled completion (load_done = 1).", $time);

        $finish;
        // can manually continue execution from here to see execution

        // Scoreboard post-flight check
        if (expected_data_q.size() > 0) begin
            $error("TEST FAILED: Data Loss! %0d words were dropped and never written to SRAM.", expected_data_q.size());
            errors++;
        end

        $display("\n================ FINAL REPORT ================");
        $display("Total Words Written: %0d", words_written);
        if (errors == 0 && UART_rx_error == 0)
            $display("RESULT: ALL TESTS PASSED! RTS/CTS handled cleanly with zero data skipped or corrupted.");
        else
            $display("RESULT: TEST FAILED with %0d scoreboard errors.", errors);
        $display("==============================================");


        // ---------------------------------------------------------------------
        // POST-LOAD FIRMWARE EXECUTION PHASE
        // ---------------------------------------------------------------------
        $display("\n============================================================");
        $display("[%0t] STARTING FIRMWARE EXECUTION PHASE", $time);
        $display("    Core reset has been released. Waiting for UART output...");
        $display("============================================================");
        // Keep the simulation running for 5,000,000 ns so the PicoRV32 core
        // can execute the firmware and transmit data via the UART peripheral.
        repeat (500_000) @(posedge clk);

        $display("\n[%0t] Firmware execution phase timed out. Ending simulation.", $time);
        $finish;
    end

endmodule