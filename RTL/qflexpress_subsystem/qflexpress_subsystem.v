`timescale 1ns / 1ps

///////////////////////////////////////////////////////////////////////////////////////////////////
// Engineer: Rakesh Patil, Shashank Tiwari, Samyak Nidhi
// Update Date: 03.04.2026
// Module Name: qflexpress_subsystem.v
// Project Name: Silicon SoC kNN
// Description:
// Encapsulates qflexpress controller integration with QSPI lane drive/sense glue.
// Preserves the exact qflexpress logic and QSPI output-enable/data-lane mapping from system.v.
///////////////////////////////////////////////////////////////////////////////////////////////////

// Uncomment for ASIC Cadence
// `include "global_defines.v"

module qflexpress_subsystem (
        input wire clk,
        input wire resetn,

        input wire i_wb_cyc,
        input wire i_wb_stb,
        input wire i_wb_ctrl_stb,
        input wire i_wb_we,
        input wire [21:0] i_wb_addr,
        input wire [31:0] i_wb_wdata,
        output wire o_wb_stall,
        output wire o_wb_ack,
        output wire [31:0] o_wb_data,

        output wire o_qspi_sck,
        output wire o_qspi_cs_n,
`ifdef FOR_ASIC
        input wire [3:0] qspi_i,
		output wire [3:0] qspi_o,
		output wire [3:0] oe_dat_out,
`else
        inout wire qspi_io_3,
        inout wire qspi_io_2,
        inout wire qspi_io_1,
        inout wire qspi_io_0,
`endif

        // Debug observability: 1 = flash header magic word matched (pass),
        // 0 = not matched yet, or matched and failed (fail).
        output wire flash_magic_word
);

wire [1:0] o_qspi_mod;
wire [3:0] o_qspi_dat;
wire [3:0] i_qspi_dat;
wire oe_dat0;
wire oe_dat1;
wire oe_dat2;
wire oe_dat3;

qflexpress #(
        // .AW( ),   // Address width
        // .DW( )    // Data width
  .OPT_ENDIANSWAP(1'b1)
) u_qflexpress (
        // Clock & Reset
        .i_clk          (clk),
        .i_reset        (resetn),

        // Wishbone interface
        .i_wb_cyc       (i_wb_cyc),
        .i_wb_stb       (i_wb_stb),
        .i_cfg_stb      (i_wb_ctrl_stb),
        .i_wb_we        (i_wb_we),
        .i_wb_addr      (i_wb_addr),
        .i_wb_data      (i_wb_wdata),

        .o_wb_stall     (o_wb_stall),
        .o_wb_ack       (o_wb_ack),
        .o_wb_data      (o_wb_data),

        // QSPI interface
        .o_qspi_sck     (o_qspi_sck),
        .o_qspi_cs_n    (o_qspi_cs_n),
        .o_qspi_mod     (o_qspi_mod),
        .o_qspi_dat     (o_qspi_dat),
        .i_qspi_dat     (i_qspi_dat)

        // Debug signals (optional)
        // .o_dbg_trigger ( ),
        // .o_debug       ( )
);

/*
 * Drive the QSPI data pins only when the flash controller enables the
 * corresponding output lanes. In single-bit mode, only data lane 0 is driven;
 * in quad mode, all four lanes are driven.
 */
`ifdef FOR_ASIC

assign i_qspi_dat = qspi_i;
assign qspi_o = o_qspi_dat;
assign oe_dat_out = {oe_dat3, oe_dat2, oe_dat1, oe_dat0};

`else

assign qspi_io_0 = oe_dat0 ? o_qspi_dat[0] : 1'bz;
assign qspi_io_1 = oe_dat1 ? o_qspi_dat[1] : 1'bz;
assign qspi_io_2 = oe_dat2 ? o_qspi_dat[2] : 1'bz;
assign qspi_io_3 = oe_dat3 ? o_qspi_dat[3] : 1'bz;

assign i_qspi_dat = {qspi_io_3, qspi_io_2, qspi_io_1, qspi_io_0};

`endif

/*
 * Output-enable mapping for the flash data lanes.
 * Mode 2'b00 keeps the controller in single-lane output mode, so only dat0 is
 * enabled. Mode 2'b10 enables all four lanes for quad output.
 */
assign oe_dat0 = (o_qspi_mod == 2'b10) || (o_qspi_mod == 2'b00);
assign oe_dat1 = (o_qspi_mod == 2'b10);
assign oe_dat2 = (o_qspi_mod == 2'b10);
assign oe_dat3 = (o_qspi_mod == 2'b10);

magic_word_observability u_magic_word_observability (
    .clk(clk),
    .resetn(resetn),

    // ADDED: Pass the control signals from the wrapper into the observability module
    .i_wb_cyc(i_wb_cyc),
    .i_wb_ctrl_stb(i_wb_ctrl_stb),
    .o_wb_ack(o_wb_ack),
    .i_wb_we(i_wb_we),

    .flash_header_data(o_wb_data),
    .flash_magic_word(flash_magic_word)
);

endmodule
