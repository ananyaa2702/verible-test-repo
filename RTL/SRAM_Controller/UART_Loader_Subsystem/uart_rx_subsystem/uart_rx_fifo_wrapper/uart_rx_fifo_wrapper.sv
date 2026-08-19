`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date: 12/16/2025 11:57:15 AM
// Design Name:
// Module Name: uart_rx_fifo_wrapper
// Project Name:
// Target Devices:
// Tool Versions:
// Description:
//
// Dependencies:
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////

module uart_rx_fifo_wrapper #(
  parameter DataLength      = 8,
  parameter BaudRate        = 115200,
  parameter FifoDepth       = 8,
  parameter SystemClockFreq = 100_000_000,
  parameter FlowControl     = 1'b1,
  parameter  DataWidth      = 8,
  parameter  Depth          = 8,
  localparam PtrWidth    = $clog2(Depth)
)(
  /* Main Signals */
  input  logic        i_rst_n,
  input  logic        i_clk,

  /* RX interface */
  output logic [7:0]  o_rx_data,
  input  logic        i_rx_req,
  output logic        o_fifo_empty,
  output logic        o_rx_error,
  output logic        o_rts,
  /* UART signals */
  input  logic        i_rx
);

  logic [DataLength-1:0] uart_rx_data;
  logic uart_rx_fifo_write_en;

  logic rx_fifo_full;
  logic rx_fifo_almost_full;
  logic [PtrWidth:0]   o_wr_ptr;
  logic [PtrWidth:0]   o_rd_ptr;

  assign o_rts = FlowControl ? ~rx_fifo_almost_full : 1'bz;

  /* ----- RX Synchronizer ----- */
  logic i_rx_sync_1, i_rx_sync_2;
  always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
      i_rx_sync_1 <= 1'b1;
      i_rx_sync_2 <= 1'b1;
    end else begin
      i_rx_sync_1 <= i_rx;
      i_rx_sync_2 <= i_rx_sync_1;
    end
  end

  /* ----- RX FIFO ----- */
  fifo #(
    .DataWidth(DataLength),
    .Depth(FifoDepth)
  ) fifo_rx (
    .i_clk     (i_clk),
    .i_rst_n   (i_rst_n),
    .i_wr_data (uart_rx_data),
    .i_wr_en   (uart_rx_fifo_write_en),
    .i_rd_en   (i_rx_req),
    .o_rd_data (o_rx_data),
    .o_full    (rx_fifo_full),
    .o_empty   (o_fifo_empty),
    .o_wr_ptr(o_wr_ptr),
    .o_rd_ptr(o_rd_ptr)
  );

  /*---- o_rts_logic----*/
  o_rts_logic #(
    .DataWidth(DataLength),
    .Depth(FifoDepth)
  )o_rts_logic (
    .i_clk     (i_clk),
    .i_rst_n   (i_rst_n),
    .uart_wr_ptr(o_wr_ptr),
    .uart_rd_ptr(o_rd_ptr),
    .o_almost_full(rx_fifo_almost_full)
  );

  /* ----- UART RX Core ----- */
  uart_rx #(
    .DataLength(DataLength),
    .SystemClockFreq(SystemClockFreq),
    .BaudRate(BaudRate)
  ) uart_rx (
    .i_clk               (i_clk),
    .i_rst_n             (i_rst_n),
    .i_rx                (i_rx_sync_2),
    .o_rx_data           (uart_rx_data),
    .o_rx_fifo_write_en  (uart_rx_fifo_write_en),
    .i_rx_fifo_full      (rx_fifo_full),
    .o_rx_error          (o_rx_error)
  );

endmodule
