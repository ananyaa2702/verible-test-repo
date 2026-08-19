`timescale 1ns / 1ps
///////////////////////////////////////////////////////////////////////////////////////////////////
// Engineer: Tanish A Shet, Samyak Nidhi, Shashank Tiwari
// Create Date: 28.03.2026
// Module Name: byte_acc
// Project Name: Silicon SoC KNN
// Description:
// Accumulate 4 bytes by reading from fifo_rx and then write to fifo_word_aligned
///////////////////////////////////////////////////////////////////////////////////////////////////

module byte_acc (
        input                   i_clk,
        input                   i_rst_n,
        input                   UART_rd_en, // Asserted by UART_loader.v
        input [7:0]             i_fifo8_rd_data,
        input                   i_fifo8_empty,
        input                   i_rx_error, // asserted by UART_rx module
        output reg [31:0]       o_fifo_word, // (32 bit / 4byte) word after reading 4 elements from FIFO
        output                  o_fifo8_rd_en, //read enable for 8bit fifo - part of UART subsystem
        output reg              word_read_done
);

//------------------------------------//
//Parameter definition for FSM states //
//------------------------------------//
parameter [1:0] IDLE       = 3'b00,
		READ_BYTE  = 3'b01,
		CAPTURE    = 3'b10;

//-------------------//
//Internal registers //
//-------------------//
reg [2:0] byte_count; //byte count = 3 implies 4bytes accumulated. Initial value of byte count is 4
reg [31:0] acc_word;
reg [7:0] incoming_byte;

//----------------//
//state registers //
//----------------//
reg [1:0] state, next_state;

/*
 * FSM state register.
 * Holds the accumulator state machine in sync with i_clk.
 */
always @ (posedge i_clk)
begin
        if(!i_rst_n)
	        state <= IDLE;
        else
	        state <= next_state;
end

/*
 * Datapath/output registers.
 * Collects bytes and emits a word once four bytes have been captured.
 */
always @ (posedge i_clk)
begin
        if(!i_rst_n)
        begin
	        byte_count <= 3'b000;
	        acc_word <= 0;
	        o_fifo_word <= 0;
	        incoming_byte <= 0;
	        word_read_done <= 0;
        end
        else
        begin
	        case(state)
	                IDLE:
		                word_read_done <= 0;
	                READ_BYTE:
                        begin
		                if(~i_fifo8_empty)
		                        incoming_byte <= i_fifo8_rd_data;
		                word_read_done <= 0;
	                end
	                CAPTURE:
                        begin
		                acc_word <= {acc_word[23:0],incoming_byte};
		                if (byte_count == 3'b011)
                                begin
		                        o_fifo_word <= {acc_word[23:0],incoming_byte};
		                        byte_count <= 3'b000;
		                        word_read_done <= 1;
                                end
                                else
		                        byte_count <= byte_count + 1;
                        end
                        default:
                        begin
                                byte_count <= 3'b000;
                                acc_word <= 0;
                                o_fifo_word <= 0;
                                incoming_byte <= 0;
                                word_read_done <= 0;
                        end
	        endcase
        end
end

/*
 * Next state decoder.
 * Chooses the subsequent FSM state based on FIFO status and byte count.
 */
always @(*)
begin
        next_state = state;
        case (state)
                IDLE:
                begin
	                if(UART_rd_en)
	                        next_state = READ_BYTE;
                        else
	                        next_state = IDLE;
                end
                READ_BYTE:
                begin
	                if(~i_fifo8_empty && ~i_rx_error)
	                        next_state = CAPTURE;
                        else
	                        next_state = READ_BYTE;
                end
                CAPTURE:
                begin
	                if(byte_count == 3'b011)
	                        next_state = IDLE;
	                else
	                        next_state = READ_BYTE;
                end
                default:
	                next_state = IDLE;
        endcase
end

assign o_fifo8_rd_en = (state == READ_BYTE && ~i_fifo8_empty);

endmodule
