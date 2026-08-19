`timescale 1ns / 1ps
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Engineer: Shashank Tiwari, Samyak Nidhi, Tanish A Shet
// Update Date: 27.03.2026
// Module Name: Reset Controller
// Project Name: Silicon SoC KNN
//
// Description:
// Module responsible for handling reset request control signals
// and driving synchronous reset(active low) to core.
// NOTE: resetn_in is the POR/ Hard_reset signal
// NOTE: resetn_core_request is the control signal driven by boot_controller - indicating
// reset must be released to core.
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

module reset_controller
(
	input           clk,
	input           resetn_core_req, resetn_in, //resetn_in is master reset mapped to external resetn swtich
	output reg      sync_core_resetn
);

reg [1:0] sync_rst;
wire rst_sync_req;

/*
 * Two-stage synchroniser for resetn_core_req.
 * Brings the asynchronous request into the clk domain safely.
 */
always @(posedge clk)
begin
	if (!resetn_in)
		sync_rst <= 2'b00;
        else
		sync_rst <= {sync_rst[0], resetn_core_req};
end

/*
 * Core reset release latch.
 * Holds the core in reset until both POR and the synchronised request go high.
 */
always @(posedge clk)
begin
	if (!resetn_in)
		sync_core_resetn <= 1'b0;// core held in reset
        else
		sync_core_resetn <= sync_core_resetn | rst_sync_req;
end

// Derive synchronised reset request signal
assign rst_sync_req = sync_rst[1];

endmodule