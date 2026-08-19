`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Shashank Tiwari, Samyak Nidhi
// Module Name: tb_uart_add(SOC_V1.1)
// Description:
// System-level TB for UART backup path.
// Flow:
//       1) mode_sel=2'b10 (UART backup mode)
//       2) boot controller holds core in reset while UART loader fills SRAM
//          with given instructions and data for a simple addition program
//       3) after load_done, core is released and executes SRAM image
//////////////////////////////////////////////////////////////////////////////////

module tb_uart_add;

    reg clk = 1'b1;
    always #5 clk = ~clk;

    reg master_resetn   = 1'b0;
    reg load_en  = 1'b0;
    reg [1:0] mode_sel = 2'b10;
    reg i_rx_tb = 1'b1; // UART idle high

    localparam [1:0] UART_MODE_SEL = 2'b10;
    // 50MHz clock + ~115200 baud UART RX (close to CLKS_PER_BIT=434 in UART RX path)
    localparam integer UART_CLKS_PER_BIT = 868;
    localparam integer UART_PAYLOAD_WORDS = 13;
    localparam integer LOAD_DONE_TIMEOUT_CYCLES = 800000;
    localparam integer APP_POSTLOAD_OBS_CYCLES  = 200000;

    // UART recovery image (COE-style) loaded into SRAM in backup mode.
    localparam [31:0] UW0  = 32'h0600_09b7;
    localparam [31:0] UW1  = 32'h0010_0a13;
    localparam [31:0] UW2  = 32'h0020_0a93;
    localparam [31:0] UW3  = 32'h0149_a023;
    localparam [31:0] UW4  = 32'h0159_a223;
    localparam [31:0] UW5  = 32'h0009_ab03;
    localparam [31:0] UW6  = 32'h0049_ab83;
    localparam [31:0] UW7  = 32'h017b_0b33;
    localparam [31:0] UW8  = 32'h0169_a023;
    localparam [31:0] UW9  = 32'h0020_09b7;
    localparam [31:0] UW10 = 32'h0040_0c13;
    localparam [31:0] UW11 = 32'h0189_a023;
    localparam [31:0] UW12 = 32'h0000_006f;

    wire trap;
    wire [9:0] gpio_out;
    wire load_busy, load_done;
    wire o_rts, UART_rx_error, UART_check_start;
    wire header_fail; // newly added port

    wire SCK, CS_N;
    wire IO_data_3, IO_data_2, IO_data_1, IO_data_0;

    integer wait_cycles;
    reg app_fetch_seen;
    reg app_result_seen;
    reg app_csr_write_seen;
    reg trap_seen;
    reg uart_load_write_seen;
    reg flash_magic_word; // magic_word match
    reg CPU_CTS = 1'b0;
    reg CPU_RTS;
    reg pcpi_valid;
    reg pcpi_ready;

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
        .CPU_UART_TRANSCEIVER_TX    (),
        .CPU_UART_TRANSCEIVER_RX    (1'b1),
        .CPU_CTS                    (CPU_CTS),           // mapped to new port
        .CPU_RTS                    (CPU_RTS),           // mapped to new port
        .pcpi_valid                 (pcpi_valid),        // mapped to new port
        .pcpi_ready                 (pcpi_ready),        // mapped to new port
        .FW_loader_UART_header_fail (header_fail)
    );

    // Keep flash model connected so top-level IOs are not floating in sim.
    W25Q16JV flash_mem (
       .CSn   (CS_N),
       .CLK   (SCK),
       .DIO   (IO_data_0),
       .DO    (IO_data_1),
       .WPn   (IO_data_2),
       .HOLDn (IO_data_3)
    );

    function [31:0] uart_word_at;
        input integer idx;
        begin
            case (idx)
                0:  uart_word_at = UW0;
                1:  uart_word_at = UW1;
                2:  uart_word_at = UW2;
                3:  uart_word_at = UW3;
                4:  uart_word_at = UW4;
                5:  uart_word_at = UW5;
                6:  uart_word_at = UW6;
                7:  uart_word_at = UW7;
                8:  uart_word_at = UW8;
                9:  uart_word_at = UW9;
                10: uart_word_at = UW10;
                11: uart_word_at = UW11;
                12: uart_word_at = UW12;
                default: uart_word_at = 32'h0000_0000;
            endcase
        end
    endfunction

    task automatic uart_wait_bit;
    begin
        repeat (UART_CLKS_PER_BIT) @(posedge clk);
    end
    endtask

    // UART frame: 1 start (0), 8 data (LSB first), 1 stop (1)
    task automatic uart_send_byte;
        input [7:0] b;
        integer i;
    begin
        i_rx_tb = 1'b0;
        uart_wait_bit();
        for (i = 0; i < 8; i = i + 1) begin
            i_rx_tb = b[i];
            uart_wait_bit();
        end
        i_rx_tb = 1'b1;
        uart_wait_bit();
    end
    endtask

    task automatic uart_send_word;
        input [31:0] w;
    begin
        // MSB first to match existing byte_acc expectations in this project.
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
        reg [31:0] header_word;
    begin
        // Header format expected by UART loader:
        // [31:16] = 16'hA5D5, [15:0] = word count
        header_word = {16'hA5D5, UART_PAYLOAD_WORDS[15:0]};
        uart_send_word_cts(header_word);
        for (wi = 0; wi < UART_PAYLOAD_WORDS; wi = wi + 1) begin
            uart_send_word_cts(uart_word_at(wi));
        end
    end
    endtask

    always @(posedge clk) begin
        // FIX: Use master_resetn for TB internal state instead of floating resetn wire
        if (!master_resetn) begin
            app_fetch_seen <= 1'b0;
            app_result_seen <= 1'b0;
            app_csr_write_seen <= 1'b0;
            trap_seen <= 1'b0;
            uart_load_write_seen <= 1'b0;
        end else begin
            // UART loader writes SRAM while core is held in reset.
            if (uut.sram_valid_uart && uut.sram_wea_uart) begin
                uart_load_write_seen <= 1'b1;
            end

            // Execution from remapped BootROM region in UART backup mode.
            if (uut.mem_valid && uut.mem_ready && uut.mem_instr && uut.core_decoder_en_remap) begin
                app_fetch_seen <= 1'b1;
            end

            if (uut.mem_valid && uut.mem_ready && !uut.mem_instr && (|uut.mem_wstrb)) begin
                if ((uut.mem_addr == 32'h0600_0000) && (uut.mem_wdata == 32'h0000_0003)) begin
                    app_result_seen <= 1'b1;
                end
                if ((uut.mem_addr == 32'h0020_0000) && (uut.mem_wdata == 32'h0000_0004)) begin
                    app_csr_write_seen <= 1'b1;
                end
            end

            if (trap) begin
                trap_seen <= 1'b1;
            end
        end
    end

    initial begin
        master_resetn = 1'b0;
        load_en = 1'b0;
        mode_sel = UART_MODE_SEL;
        i_rx_tb = 1'b1;

        app_fetch_seen = 1'b0;
        app_result_seen = 1'b0;
        app_csr_write_seen = 1'b0;
        trap_seen = 1'b0;
        uart_load_write_seen = 1'b0;

        repeat (20) @(posedge clk);
        master_resetn = 1'b1;

        // FIX: Replaced wait (resetn === 1) with a fixed delay to allow internal synchronizer to clear
        repeat (20) @(posedge clk);

        // Kick UART backup load.
        @(posedge clk); load_en = 1'b1;
        repeat (5) @(posedge clk);
        @(posedge clk); load_en = 1'b0;

        // Send header + payload while core is in reset.
        send_uart_payload();

        // Wait for UART loader path to report done.
        wait_cycles = 0;
        while (!load_done && wait_cycles < LOAD_DONE_TIMEOUT_CYCLES) begin
            @(posedge clk);
            wait_cycles = wait_cycles + 1;
        end

        // Observe post-load execution window.
        wait_cycles = 0;
        while ((!app_fetch_seen || !app_result_seen || !app_csr_write_seen) &&
               wait_cycles < APP_POSTLOAD_OBS_CYCLES) begin
            @(posedge clk);
            wait_cycles = wait_cycles + 1;
        end

        $display("UART_BACKUP_SUMMARY: load_done=%0d uart_load_write_seen=%0d app_fetch_seen=%0d app_result_seen=%0d app_csr_write_seen=%0d trap_seen=%0d",
                 load_done, uart_load_write_seen, app_fetch_seen, app_result_seen, app_csr_write_seen, trap_seen);

        if (!load_done)
            $display("UART_BACKUP_FAIL: load_done did not assert.");
        if (!uart_load_write_seen)
            $display("UART_BACKUP_FAIL: no UART writes into SRAM were observed.");
        if (!app_fetch_seen)
            $display("UART_BACKUP_FAIL: no post-release instruction fetch from remapped SRAM was observed.");
        if (!app_result_seen)
            $display("UART_BACKUP_FAIL: core did not write result 0x3 to 0x0600_0000.");
        if (!app_csr_write_seen)
            $display("UART_BACKUP_FAIL: core did not write done marker 0x4 to 0x0020_0000.");

        $finish;
    end

endmodule