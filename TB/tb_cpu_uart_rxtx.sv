`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Rohith Suju
// Module Name: tb_uart_rx_test
// Description:
// Testbench to test UART RX functionality of CPU Side UART
//////////////////////////////////////////////////////////////////////////////////

`define FAST_LOAD

module tb_cpu_uart_rxtx ();

        reg clk = 1'b1;
        always #5 clk = ~clk;

        wire resetn;
        reg load_en = 1'b0;
        reg switch = 1'b0;
        reg [1:0] mode_sel = 2'b10;

        wire uart_tx;
        wire [7:0] recv_data;
        wire data_valid_rcv;
        wire trap;
        wire [9:0] gpio_out;
        wire load_busy;
        wire load_done;
        wire o_rts;
        wire UART_rx_error;
        wire UART_check_start;
        wire SCK;
        wire CS_N;
        wire IO_data_3;
        wire IO_data_2;
        wire IO_data_1;
        wire IO_data_0;
        wire flash_magic_word;
        wire CPU_CTS = 1'b0;
        wire CPU_RTS;
        wire pcpi_valid;
        wire pcpi_ready;
        wire header_fail;


        reg        qspi_oe;
        reg [3:0]  qspi_out;
        wire [3:0] qspi_in;

        reg master_resetn = 1'b0;
        integer wait_cycles;

        // FIX: Removed reset_synch for post-synth compatibility and tied the wire directly
        assign resetn = master_resetn;

        // System UART TX monitor keeps the bench consistent with the flash test.
        uart_rx_sim u_uart_rx_mon (
                .clk(clk),
                .resetn(resetn),
                .rx(uart_tx),
                .data_out(recv_data),
                .data_valid(data_valid_rcv)
        );

        // UART transmitter stimulus that feeds the SoC load input.
        wire tx_stim_out;
        wire [2:0] tx_state;
        wire [4:0] tx_count;
        reg [7:0] tx_data = 8'hA5;
        reg tx_push = 1'b0;
        reg [31:0] uart_tick_acc = 32'd0;
        reg uart_enable = 1'b0;

        localparam [1:0] FLASH_MODE_SEL = 2'b00;

        localparam integer CLK_FREQ_HZ = 100_000_000;
        localparam integer UART_BAUD = 115_200;
        localparam integer UART_OVERSAMPLE = 16;
        localparam integer UART_TICK_RATE = UART_BAUD * UART_OVERSAMPLE;
        localparam integer UART_TICK_MODULO = CLK_FREQ_HZ;

        uart_transmitter tx_stim (
                .clk(clk),
                .wb_rst_i(resetn),
                .lcr(8'b0000_0011),
                .tf_push(tx_push),
                .wb_dat_i(tx_data),
                .enable(uart_enable),
                .stx_pad_o(tx_stim_out),
                .tstate(tx_state),
                .tf_count(tx_count),
                .tx_reset(~resetn),
                .lsr_mask(~resetn)
        );

        W25Q16JV flash_mem (
                .CSn   (CS_N),
                .CLK   (SCK),
                .DIO   (IO_data_0),
                .DO    (IO_data_1),
                .WPn   (IO_data_2),
                .HOLDn (IO_data_3)
        );

        assign IO_data_0 = qspi_oe ? qspi_out[0] : 1'bz;
        assign IO_data_1 = qspi_oe ? qspi_out[1] : 1'bz;
        assign IO_data_2 = qspi_oe ? qspi_out[2] : 1'bz;
        assign IO_data_3 = qspi_oe ? qspi_out[3] : 1'bz;
        assign qspi_in = {IO_data_3, IO_data_2, IO_data_1, IO_data_0};

        system uut (
                .clk              (clk),
                .master_resetn    (master_resetn),
                .trap             (trap),
                .gpio_out         (gpio_out),
                .load_en_asynch          (load_en),
                .FW_loader_UART_i_rx (1'b1),
                .mode_sel_asynch         (mode_sel),
                .load_busy        (load_busy),
                .load_done        (load_done),
                .FW_loader_UART_o_rts            (o_rts),
                .FW_loader_UART_rx_error    (UART_rx_error),
                .FW_loader_UART_check_start (UART_check_start),
                .o_qspi_sck       (SCK),
                .o_qspi_cs_n      (CS_N),
                .qspi_io_3        (IO_data_3),
                .qspi_io_2        (IO_data_2),
                .qspi_io_1        (IO_data_1),
                .qspi_io_0        (IO_data_0),
                .flash_magic_word   (flash_magic_word),
                .CPU_UART_TRANSCEIVER_TX   (uart_tx),
                .CPU_UART_TRANSCEIVER_RX   (tx_stim_out),
                .CPU_CTS                   (CPU_CTS),
                .CPU_RTS                   (CPU_RTS),
                .pcpi_valid                (pcpi_valid),
                .pcpi_ready                (pcpi_ready),
                .FW_loader_UART_header_fail(header_fail)
        );

        always @(posedge clk or negedge resetn)
	begin
                if (!resetn)
		begin
                        uart_tick_acc <= 32'd0;
                        uart_enable <= 1'b0;
                end else
		begin
                        if (uart_tick_acc + UART_TICK_RATE >= UART_TICK_MODULO)
			begin
                                uart_tick_acc <= uart_tick_acc + UART_TICK_RATE - UART_TICK_MODULO;
                                uart_enable <= 1'b1;
                        end
			else
			begin
                                uart_tick_acc <= uart_tick_acc + UART_TICK_RATE;
                                uart_enable <= 1'b0;
                        end
                end
        end

        always @(posedge clk)
	begin
                if (data_valid_rcv)
                        $display("UART TX: 0x%02h", recv_data);
        end

	`ifdef FAST_LOAD
        initial
	begin
                // Wait a brief moment for the IP's internal logic to settle
                #1;

                // Inject the new firmware directly into the simulation array change this for fast bootrom loading
                $readmemh("bootrom_cpu_uart_rxtx.memh",
                        uut.u_bootrom_wrapper.bootrom.inst.native_mem_module.blk_mem_gen_v8_4_12_inst .memory);

                $display("TB_NOTE: Fast-loaded custom firmware into BootROM bypassing synthesis!");
        end
        `endif

        initial
	begin
                load_en = 1'b0;
                mode_sel = FLASH_MODE_SEL;
                qspi_oe  = 1'b0;
                qspi_out = 4'h0;

                tx_push = 1'b0;
                tx_data = 8'hA5;

                repeat (20) @(posedge clk);
                master_resetn = 1'b1;

                wait (resetn === 1'b1);
                repeat (16) @(posedge clk);

                // Allow flash model startup before issuing reads.
                repeat (35000) @(posedge clk);

                // Start the core by pulsing load_en
                @(posedge clk);
                load_en = 1'b1;
                @(posedge clk);
                load_en = 1'b0;

                repeat(5) @(posedge clk);

                // Keep streaming UART data while the system continues running.
                forever
		begin
                        send_uart_byte(tx_data);
                        tx_data = tx_data + 8'h01;
                        // 1 start bit + 8 data bits + 1 stop bit = 10 bits per UART frame, so we wait 10 bit times
                        // 100 MHz clock / 115200 baud = ~868 cycles per bit, so 868 * 10 = 8680 cycles per frame
                        repeat (8680) @(posedge clk);
                end
        end

        task send_uart_byte(input [7:0] value);
        begin
        	tx_data = value;
                @(posedge clk);
                tx_push = 1'b1;
                @(posedge clk);
                tx_push = 1'b0;
                repeat (2) @(posedge clk);
        end
        endtask

endmodule