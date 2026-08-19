`timescale 1ns / 1ps

///////////////////////////////////////////////////////////////////////////////////////////////////
// Engineer: Shashank Tiwari, Samyak Nidhi, Tanish A Shet, Rakesh Patil
// Update Date: 03.04.2026
// Module Name: CPU_SPI_WB_bridge.v
// Project Name: Silicon SoC KNN
// Description:
// Native CPU memory to Wishbone bridge for the SPI flash controller path.
// Issues one transaction at a time, preserves bus timing with a simple IDLE/BUSY FSM,
// and returns read data to the CPU one cycle after Wishbone acknowledge.
///////////////////////////////////////////////////////////////////////////////////////////////////

module mem_to_wb_bridge #(
        parameter integer AW = 22, // must match: wbqspiflash AW = ADDRESS_WIDTH-2
        parameter [31:0] CTRL_BASE = 32'h0010_0000, // base address for control regs
        parameter [31:0] CTRL_MASK = 32'hFFFF0000 // mask to select control region
)(
        input wire clk,
        input wire resetn,

        // CPU side (core native memory interface)
        input wire cpu_mem_valid,
        input wire cpu_mem_instr, // not used here, available for optimization
        output reg cpu_mem_ready,
        input wire [31:0] cpu_mem_addr,
        input wire [31:0] cpu_mem_wdata,
        input wire [3:0] cpu_mem_wstrb,
        output wire [31:0] cpu_mem_rdata_,

        // Wishbone side expected by wbqspiflash
        output reg i_wb_cyc,
        output reg i_wb_data_stb,
        output reg i_wb_ctrl_stb,
        output reg i_wb_we,
        output reg [(AW-1):0] i_wb_addr, // word address (drop lowest 2 bits)
        output reg [31:0] i_wb_data,
        input wire o_wb_stall,
        input wire o_wb_ack,
        input wire [31:0] o_wb_data,
        input wire addr_is_ctrl
);

//----------------------------------//
// FSM state encoding               //
//----------------------------------//
localparam IDLE = 1'b0, BUSY = 1'b1;

//----------------------------------//
// Internal state/data registers    //
//----------------------------------//
reg state;
reg rsp_pending;
reg [31:0] cpu_mem_rdata;

//----------------------------------//
// Word-address extraction          //
//----------------------------------//
// Flash/Wishbone path is word-addressed, so drop the two LSBs.
wire [(AW-1):0] cpu_word_addr = cpu_mem_addr[AW+1:2];

/*
 * Single-transaction Wishbone bridge FSM.
 * IDLE: accepts one CPU request when bus is not stalled.
 * BUSY: waits for o_wb_ack, then schedules a one-cycle-later CPU response.
 */
always @(posedge clk)
begin
        if (!resetn)
        begin
                state <= IDLE;
                i_wb_cyc <= 1'b0;
                i_wb_data_stb <= 1'b0;
                i_wb_ctrl_stb <= 1'b0;
                i_wb_we <= 1'b0;
                i_wb_addr <= {(AW){1'b0}};
                i_wb_data <= 32'h00000000;
                cpu_mem_ready <= 1'b0;
                cpu_mem_rdata <= 32'h00000000;
                rsp_pending <= 1'b0;
        end
        else
        begin
                // Default: ready is a one-cycle pulse.
                cpu_mem_ready <= 1'b0;

                // Return response one cycle after acknowledge to ensure stable data capture.
                if (rsp_pending)
                begin
                        cpu_mem_rdata <= o_wb_data;
                        cpu_mem_ready <= 1'b1;
                        rsp_pending <= 1'b0;
                end

                case (state)
                        IDLE:
                        begin
                                // Start transaction only when CPU requests and slave is not stalled.
                                if (cpu_mem_valid && !o_wb_stall)
                                begin
                                        i_wb_cyc <= 1'b1;
                                        i_wb_we <= (|cpu_mem_wstrb) ? 1'b1 : 1'b0;
                                        i_wb_addr <= cpu_word_addr;
                                        i_wb_data <= cpu_mem_wdata;

                                        if (addr_is_ctrl)
                                        begin
                                                i_wb_ctrl_stb <= 1'b1;
                                                i_wb_data_stb <= 1'b1;
                                        end
                                        else
                                        begin
                                                i_wb_data_stb <= 1'b1;
                                                i_wb_ctrl_stb <= 1'b0;
                                        end

                                        state <= BUSY;
                                end
                        end

                        BUSY:
                        begin
                                // Keep transaction active until acknowledge.
                                if (o_wb_ack)
                                begin
                                        rsp_pending <= 1'b1;
                                        i_wb_cyc <= 1'b0;
                                        i_wb_data_stb <= 1'b0;
                                        i_wb_ctrl_stb <= 1'b0;
                                        i_wb_we <= 1'b0;
                                        state <= IDLE;
                                end
                                else
                                        i_wb_cyc <= 1'b1;
                        end

                        default:
                        begin
                                state <= IDLE;
                                i_wb_cyc <= 1'b0;
                                i_wb_data_stb <= 1'b0;
                                i_wb_ctrl_stb <= 1'b0;
                                i_wb_we <= 1'b0;
                                i_wb_addr <= {(AW){1'b0}};
                                i_wb_data <= 32'h00000000;
                                cpu_mem_ready <= 1'b0;
                        end
                endcase
        end
end

// CPU read-data output mapping.
assign cpu_mem_rdata_ = cpu_mem_rdata;

endmodule