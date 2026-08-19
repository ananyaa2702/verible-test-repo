`timescale 1ns / 1ps
///////////////////////////////////////////////////////////////////////////////////////////////////
// Engineer: Rakesh Patil, Shashank Tiwari, Samyak Nidhi
// Update Date: 03.04.2026
// Module Name: magic_word_observability.v
// Project Name: Silicon SoC kNN
// Description:
// Logic to observe the magic word in the flash header.
// This module is used for debug observability.
// This module is not part of the qflexpress controller and is only used for debug purposes.
// It monitors the flash header and asserts the flash_magic_word output when the magic word is matched.
///////////////////////////////////////////////////////////////////////////////////////////////////

// Uncomment for ASIC Cadence
// `include "global_defines.v"

module magic_word_observability (
	input wire clk,
    	input wire resetn,

    	// ADDED: Missing Wishbone control signals needed for logic
    	input wire i_wb_cyc,
    	input wire i_wb_ctrl_stb,
    	input wire o_wb_ack,
    	input wire i_wb_we,

    	input wire [31:0] flash_header_data,
    	output wire flash_magic_word
);

localparam FW_MAGIC_WORD = 32'hB007B007;

reg [31:0] obs_word;
reg [2:0]  obs_byte_count;
reg        obs_latched;
reg        obs_byte_pending;
reg        o_flash_magic_word;

// FIX: Now using the ports correctly
wire obs_write_ack    = i_wb_cyc && i_wb_ctrl_stb && o_wb_ack && i_wb_we;
wire obs_read_ack     = i_wb_cyc && i_wb_ctrl_stb && o_wb_ack && !i_wb_we;
wire obs_capture_now  = obs_read_ack && obs_byte_pending && !obs_latched;

assign flash_magic_word = o_flash_magic_word;

// FIX: Use flash_header_data instead of undeclared o_wb_data
wire [31:0] obs_word_next = {flash_header_data[7:0], obs_word[31:8]};

always @(posedge clk)
begin
	if (!resetn)
	begin
        	obs_word           <= 32'h0;
        	obs_byte_count     <= 3'd0;
        	obs_latched        <= 1'b0;
        	obs_byte_pending   <= 1'b0;
        	o_flash_magic_word <= 1'b0;
    	end
	else
	begin
        	if (obs_write_ack)
            		obs_byte_pending <= 1'b1;
        	else if (obs_capture_now)
            		obs_byte_pending <= 1'b0;
        	else
            		obs_byte_pending <= obs_byte_pending;

        	if (obs_capture_now)
		begin
            		obs_word <= obs_word_next;
            		if (obs_byte_count == 3'd3)
			begin
                		if (obs_word_next == FW_MAGIC_WORD)
                    			o_flash_magic_word <= 1'b1;
                		else
                    			o_flash_magic_word <= 1'b0;

                	obs_latched    <= 1'b1;
                	obs_byte_count <= 3'd0;
            		end
	    		else
			begin
                		obs_byte_count     <= obs_byte_count + 3'd1;
                		obs_latched        <= obs_latched;
                		o_flash_magic_word <= o_flash_magic_word;
            		end
        	end
		else
		begin
            		obs_word           <= obs_word;
            		obs_byte_count     <= obs_byte_count;
            		obs_latched        <= obs_latched;
            		o_flash_magic_word <= o_flash_magic_word;
        	end
    	end
end

endmodule