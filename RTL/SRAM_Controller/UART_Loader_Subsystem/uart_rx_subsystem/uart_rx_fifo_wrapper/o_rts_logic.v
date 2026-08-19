`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Shashank Tiwari, Samyak Nidhi, Tanish A Shet
// Create Date: 28.03.2026
// Module Name: o_rts_logic
// Project Name: Silicon SoC KNN
// Description:
// wr_ptr increments 1 cycle ahead of rd_ptr in the given design.
// This leads o_rts conflict when in a given clock cycle rd_ptr = 1111 and
// wr_ptr circles back to 0000.
// This logic deals with issue and prevents unnecessary falls in o_rts logic.
//////////////////////////////////////////////////////////////////////////////////


module o_rts_logic #(
        parameter              DataWidth = 8,
        parameter              Depth = 8,
        localparam             PtrWidth = $clog2(Depth),
        parameter [PtrWidth:0] Almost_Full_Th = Depth-2
) (
        input              i_clk,
        input              i_rst_n,
        input [PtrWidth:0] uart_wr_ptr,
        input [PtrWidth:0] uart_rd_ptr,
        output reg         o_almost_full
);

localparam [PtrWidth:0] RD_PTR_MAX = {1'b1, {PtrWidth{1'b1}}};  // e.g., 1111 for Depth=8
localparam [PtrWidth:0] WR_PTR_WRAP = {1'b0, {PtrWidth{1'b0}}}; // e.g., 0000 for Depth=8

reg [1:0] counter;
wire [1:0] next_counter;

// Detect the wrap-around edge case where rd_ptr is at max and wr_ptr wraps to 0
wire wrap_condition;

/*
 * Wrap counter book-keeping.
 * Tracks how long we sit in the rd_ptr=max/wr_ptr=0 corner case.
 */
always@(posedge i_clk)
begin
        if (!i_rst_n)
	        counter <= 0;
        else if (wrap_condition)
        begin
	        if (counter < 3)
	                counter <= next_counter;
        end
        else
	        counter <= 0;
end

/*
 * RTS gating combinational logic.
 * Decides whether to deassert o_almost_full based on fill level and wrap window.
 */
always@(*)
begin
        if ((uart_wr_ptr - uart_rd_ptr) >= Almost_Full_Th)
        begin
	        if (wrap_condition && counter <= 1)
	                o_almost_full = 0;
                else
	                o_almost_full = 1;
        end
        else
	        o_almost_full = 0;
end

assign wrap_condition = (uart_rd_ptr == RD_PTR_MAX) && (uart_wr_ptr == WR_PTR_WRAP);
assign next_counter = counter + 1'b1;

endmodule