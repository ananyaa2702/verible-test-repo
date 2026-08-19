`timescale 1ns / 1ps

///////////////////////////////////////////////////////////////////////////////////////////////////
// Engineer: Rakesh Patil, Shashank Tiwari, Samyak Nidhi
// Update Date: 03.04.2026
// Module Name: core_addr_forward.v
// Project Name: Silicon SoC kNN
// Description:
// Extracted core transaction-forwarding logic from system.v.
// Contains the original control-state sequencer and read-data/ready response mux with unchanged behavior.
///////////////////////////////////////////////////////////////////////////////////////////////////

module core_addr_forward #(
        parameter [31:0] GPIO_OUT_ADDR             = 32'h0500_0000,
        parameter [31:0] SPI_ACCESS_REG_BASE       = 32'h0100_0000,
        parameter [31:0] SPI_ACCESS_REG_END        = 32'h01FF_FFFF,
        parameter [31:0] SPI_CTRL_REG              = 32'h0010_0000,
        parameter [31:0] UART_TRANSCEIVER_REG_BASE = 32'h0300_0000,
        parameter [31:0] UART_TRANSCEIVER_REG_END  = 32'h0300_00FF,
        parameter [31:0] SRAM_REG_START            = 32'h0600_0000,
        parameter [31:0] SRAM_REG_END              = 32'h0600_3FFC,
        parameter [31:0] SRAM_CSR_BASE             = 32'h0020_0000
) (
        input wire clk,
        input wire resetn,
        input wire mem_instr,
        input wire mem_valid,
        input wire [31:0] mem_addr,
        input wire [31:0] mem_wdata,
        input wire [3:0] mem_wstrb,
        input wire core_decoder_en_remap,
        input wire flash_ready,
        input wire [31:0] flash_rdata,
        input wire uart_transceiver_ready,
        input wire [31:0] uart_txrx_rdata,
        input wire sram_ready,
        input wire [31:0] SRAM_RDATA,
        input wire bootrom_valid,
        input wire bootrom_ready,
        input wire [31:0] bootrom_rdata,
        input wire SRAM_CSR_ready,
        input wire [31:0] CSR_rdata,
        output reg [9:0] gpio_reg,
        output reg m_read_en,
        output reg bootrom_wea,
        output wire sram_valid_core,
        output wire sram_wea_core,
        output reg SRAM_CSR_VALID,
        output reg spi_mem_valid,
        output reg addr_is_ctrl,
        output reg [31:0] spi_cpu_mem_addr_latched,
        output reg is_uart_access,
        output reg uart_transceiver_valid,
        output reg mem_ready,
        output reg [31:0] mem_rdata
);

/*
 * Update the control and access state on the clock edge.
 * This block sequences boot, GPIO, SPI, UART, SRAM, and CSR control paths
 * without changing any of the transaction timing or decode conditions.
 */
always @(posedge clk)
begin
        if (!resetn) begin
                gpio_reg <= 0;
                m_read_en <= 0;
                bootrom_wea <= 0;
                // sram_valid_core <= 0;
                // sram_wea_core <= 0;
                SRAM_CSR_VALID <= 0;
                spi_mem_valid <= 0;
                addr_is_ctrl <= 0;
                spi_cpu_mem_addr_latched <= 32'b0;
        end
        else
        begin
                // Default assignments
                m_read_en <= 0;
                bootrom_wea <= 0;
                is_uart_access <= 0;
                uart_transceiver_valid <= 0;
                // sram_valid_core <= 0;
                // sram_wea_core <= 0;
                SRAM_CSR_VALID <= 0;

                /*
                 * 1. BootROM access.
                 * Uses the instantaneous bootrom_valid condition to avoid the extra cycle delay.
                 */
                if (bootrom_valid && !mem_ready && !core_decoder_en_remap)
                begin
                        bootrom_wea <= 1'b0;
                end

                /*
                 * 2. GPIO write.
                 * Updates the GPIO output register.
                 */
                else if (!mem_instr && mem_valid && mem_ready && (mem_addr == GPIO_OUT_ADDR) && (|mem_wstrb))
                begin
                        gpio_reg <= mem_wdata[9:0];
                end

                /*
                 * 3. SPI flash access sequencing.
                 * Hold an active SPI transaction until the flash controller responds,
                 * keeping the current SPI owner stable while the request is in flight.
                 */
                else if (spi_mem_valid)
                begin
                        if (flash_ready)
                        begin
                                spi_mem_valid <= 1'b0;
                                addr_is_ctrl <= 1'b0;
                        end
                end

                /*
                 * 4. SPI access initiation.
                 * Start a new SPI request when the CPU addresses the SPI window
                 * and no SPI transaction is already active.
                 * addr_is_ctrl selects control-register access versus flash data access.
                 */
                else if ((mem_valid && (mem_addr >= SPI_ACCESS_REG_BASE) && (mem_addr <= SPI_ACCESS_REG_END)) ||
                        (mem_valid && !mem_instr && (mem_addr == SPI_CTRL_REG)))
                begin
                        addr_is_ctrl <= (mem_addr == SPI_CTRL_REG);
                        spi_cpu_mem_addr_latched <= (mem_addr == SPI_CTRL_REG) ? 32'h0000_0000 : (mem_addr - SPI_ACCESS_REG_BASE);
                        spi_mem_valid <= 1'b1;
                end

                /*
                 * 5. UART transceiver access.
                 * Forwards the UART window transaction into the UART bridge path.
                 */
                else if (mem_valid && (mem_addr >= UART_TRANSCEIVER_REG_BASE) && (mem_addr <= UART_TRANSCEIVER_REG_END))
                begin
                        is_uart_access <= 1;
                        uart_transceiver_valid <= mem_valid;
                end

                /*
                 * 6. SRAM access.
                 * Handles normal CPU reads and writes to the SRAM window.
                 */
                // else if (mem_valid && !mem_ready && (((mem_addr >= SRAM_REG_START) && (mem_addr <= SRAM_REG_END)) ||
                //         core_decoder_en_remap))
                // begin
                //         sram_wea_core <= |mem_wstrb;
                //         sram_valid_core <= mem_valid;
                // end

                /*
                 * 7. SRAM CSR access.
                 * Provides load-status access through the SRAM CSR address.
                 */
                else if (mem_valid && (mem_addr == SRAM_CSR_BASE))
                        SRAM_CSR_VALID <= mem_valid;

                else
                begin
                        bootrom_wea <= 0;
                        is_uart_access <= 0;
                        uart_transceiver_valid <= 0;
                        // sram_valid_core <= 0;
                        // sram_wea_core <= 0;
                        SRAM_CSR_VALID <= 0;
                end
        end
end

 assign sram_valid_core = mem_valid && (((mem_addr >= SRAM_REG_START) && (mem_addr <= SRAM_REG_END)) || core_decoder_en_remap);
 assign sram_wea_core   = sram_valid_core ? (|mem_wstrb) : 1'b0;

/*
 * Select the active read data and ready source.
 * This block multiplexes the response from SPI flash, UART, SRAM, BootROM,
 * SRAM CSR, and GPIO accesses based on the current transaction owner.
 */
always @(*)
begin
	if (bootrom_valid)
        begin
                mem_ready = bootrom_ready;
                mem_rdata = bootrom_rdata;
	end
	else if (sram_valid_core)
        begin
                mem_ready = sram_ready; // SRAM read is ready after 1 cycle latency
                mem_rdata = SRAM_RDATA;
        end
        else if (spi_mem_valid)
        begin
                mem_ready = flash_ready;
                mem_rdata = flash_rdata;
        end
        else if (uart_transceiver_valid)
        begin
                mem_ready = uart_transceiver_ready;
                mem_rdata = uart_txrx_rdata;
        end
        else if (SRAM_CSR_VALID)
        begin
                mem_ready = SRAM_CSR_ready;
                mem_rdata = CSR_rdata;
        end
        else if (!mem_instr && mem_valid && (mem_addr == GPIO_OUT_ADDR))
        begin
                mem_ready = 1'b1;
                mem_rdata = {22'b0, gpio_reg};
        end
        else
        begin
                mem_ready = 1'b0; // Default case - no ready signal
                mem_rdata = 32'h00000000; // Default case - return 0
        end
end

endmodule
