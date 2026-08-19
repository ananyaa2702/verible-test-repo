`timescale 1ns / 1ps
/////////////////////////////////////////////////////////////////////////////
// Engineer: Tanish A Shet, Samyak Nidhi, Shashank Tiwari
// Updated Date: 28.03.2026
// Module Name: UART_loader
// Project Name: Silicon SoC KNN
// Description:
// Module responsible for reading from FIFO connected to UART receiver,
// processing the header, and writing firmware data to SRAM.
// The module implements a finite state machine (FSM) to manage the different
// stages of the firmware loading process, including idle, header reading,
// header checking, data loading, and completion. It also interfaces with
// the BRAM IP by generating the necessary control signals for valid and
// write enable during SRAM writes.
//////////////////////////////////////////////////////////////////////////////////

module UART_loader
#(
        parameter          W = 32,
        parameter          N = 14
)(
        input              clk,
        input              resetn_in,
        input              UART_load_en,
        input [W-1:0]      UART_rdata,
        input              word_read_done,
        output reg         UART_load_done,
        output reg [W-1:0] UART_SRAM_WDATA,
        output reg [N-1:0] UART_SRAM_ADDR,
        output reg         UART_load_busy,
        output reg         UART_check_start,
        output reg         UART_rd_en,
        output reg         header_fail,

        // BRAM IP Specific Interfacing Signals
        output reg         sram_valid_uart,
        output reg         sram_wea_uart
);

//------------------------------------//
//parameter definition for FSM states //
//------------------------------------//
parameter [2:0] IDLE = 3'b000,
		READ_HEADER = 3'b001,
		CHECK_HEADER = 3'b010,
		LOAD = 3'b011,
		DONE = 3'b100;

//-------------------------------------//
//Parameter for CONST UART word header //
//-------------------------------------//
parameter [15:0] CHECK_HALF_WORD = 16'hA5D5;
parameter [N-1:0] BASE_ADDR  = {N{1'b0}};  // SRAM base offset (0x000)

reg header_captured;
reg [N-1:0] next_UART_SRAM_ADDR;
reg [15:0] next_words_left;
reg load_completed;  // Flag to prevent re-triggering after load completes

//----------------------------//
// State register declaration //
//----------------------------//
reg [2:0] state, next_state;

reg [15:0] words_left; // reg to keep track of firmware words
reg [31:0] HEADER_WORD;
reg handshake_pass ;
reg first_word_written; // Flag to indicate first word written after header
wire start;

/*
 * FSM state register.
 * Tracks the loader state machine position synchronously with clk.
 */
always @ (posedge clk)
begin
        if(!resetn_in)
                state <= IDLE;
        else
	        state <= next_state;
end

/*
 * Output/data register bank.
 * Captures all UART loader side-effects and datapath registers per state.
 */
always @(posedge clk)
begin
        if(!resetn_in)
        begin
	        UART_load_busy <= 0;
	        UART_load_done <= 0;
	        UART_rd_en <= 0;
	        words_left <= 0;
	        UART_SRAM_ADDR <= BASE_ADDR;
	        HEADER_WORD <= 32'h0000_0000;
	        handshake_pass <= 0;
	        UART_check_start <= 0;
	        header_captured <= 0;
	        UART_SRAM_WDATA <= 0;
	        first_word_written <= 0;
	        load_completed <= 0;
	        header_fail <= 0;
	        sram_valid_uart <= 0;
        	sram_wea_uart <= 0;

        end
        else
        begin
	        // Update registers from combinational next values
	        words_left <= next_words_left;
	        UART_SRAM_ADDR <= next_UART_SRAM_ADDR;
	        sram_valid_uart <= 0;
	        sram_wea_uart <= 0;

	        case(state)
	                IDLE:
                        begin
		                UART_rd_en <= 0;
		                UART_load_busy <= 0;
		                header_captured <= 0;
		                HEADER_WORD <= 32'h0000_0000;
		                first_word_written <= 0;

                                /*
		                 * Clear load_completed flag only when UART_load_en goes LOW
		                 * This allows a new load to be initiated after the current
                                 * one completes
                                 */
		                if(!start)
                                begin
		                        load_completed <= 0;
		                        UART_load_done <= 0;
		                        UART_check_start <= 0;
		                end
                                else if(start && !load_completed)
		                        UART_check_start  <= 1;
		                else
		                        UART_check_start  <= 0;
	                end
                        /*
                         * Read the header from UART and capture it in HEADER_WORD.
                         * This header contains the handshake value and the number
                         * of words to load.
                         */
	                READ_HEADER:
                        begin
		                header_fail <= 0;
		                UART_check_start <= 0;
		                if(!header_captured)
                                begin
		                        if(!UART_rd_en && !word_read_done)
			                        UART_rd_en <= 1;
		                        else if(word_read_done && UART_rd_en)
                                        begin
			                        HEADER_WORD <= UART_rdata;
			                        UART_rd_en  <= 0;
			                        header_captured <= 1;
                                        end
                                        else
                                        begin
                                                UART_rd_en <= UART_rd_en;
                                                HEADER_WORD <= HEADER_WORD;
                                                header_captured <= header_captured;
                                        end
		                end
                                else
		                        UART_rd_en <= 0;
	                end
	                CHECK_HEADER:
                        begin
		                UART_rd_en <= 0;
		                if(HEADER_WORD[31:16] == CHECK_HALF_WORD)
		                        handshake_pass <= 1;
		                else
                                begin
		                        handshake_pass <= 0;
		                        header_fail <= 1;
		                        header_captured <= 0;
		                        UART_load_busy <= 0;
		                end
	                end
	                LOAD:
                        begin
		                UART_load_busy <= 1;
		                if(words_left > 0)
                                begin
			                if(!word_read_done && !UART_rd_en)
			                        UART_rd_en <= 1;
			                else if(word_read_done && UART_rd_en)
                                        begin
			                        UART_SRAM_WDATA <= UART_rdata;
			                        UART_rd_en <= 0;
			                        first_word_written <= 1;

			                        // Assert controller SRAM write for one cycle
			                        sram_valid_uart <= 1;
			                        sram_wea_uart <= 1;
	                                end
                                        else
                                        begin
		                                UART_rd_en <= UART_rd_en;
		                                first_word_written <= first_word_written;

		                                // keep SRAM strobes low while waiting for a clean handshake
		                                sram_valid_uart <= 1'b0;
		                                sram_wea_uart <= 1'b0;
	                                end
		                end
                                else
                                begin
			                UART_rd_en <= 0;
			                UART_load_busy <= 0;
		                end
	                end
                        /*
                         * Once all words are loaded, assert load_done for one cycle and
                         * return to IDLE. The load_completed flag prevents re-triggering
                         * until UART_load_en goes low again.
                         */
	                DONE:
                        begin
		                UART_rd_en <= 0;
		                UART_load_busy <= 0;
		                UART_load_done <= 1;
		                load_completed <= 1;
	                end
                        default:
                        begin
		                UART_rd_en <= 0;
		                UART_load_busy <= 0;
		                UART_load_done <= 0;
		                handshake_pass <= 0;
		                header_captured <= 0;
		                first_word_written <= 0;
		                header_fail <= 0;
	                end
	        endcase
        end
end

/*
 * Next-state logic.
 * Pure combinational decoder for upcoming state, word counts, and addresses.
 */
always @ (*)
begin
        // Default Assignments to prevent latches
        next_state = state;
        next_words_left = words_left;
        next_UART_SRAM_ADDR = UART_SRAM_ADDR;

        case(state)
	        IDLE:
                begin
	                next_UART_SRAM_ADDR = BASE_ADDR;
	                next_words_left = 16'd0;
	                if(start && !load_completed)
		                next_state = READ_HEADER;
                        else
		                next_state = IDLE;
                end
	        READ_HEADER:
                begin
	                if(word_read_done)
		                next_state = CHECK_HEADER;
                        else
		                next_state = READ_HEADER;
	        end
	        CHECK_HEADER:
                begin
	                if(HEADER_WORD[31:16] == CHECK_HALF_WORD)
                        begin
		                next_state = LOAD;
		                next_words_left = HEADER_WORD[15:0];
	                end
                        else
                        begin
		                next_state = DONE; //handshake failure treated as completed load
		                next_words_left = 16'h0000;
	                end
	        end
	        LOAD:
                begin
	                if(words_left>0)
                        begin
		                next_state = LOAD;
		                if(word_read_done && UART_rd_en)
                                begin
		                        next_words_left = words_left - 1;
		                        /*
                                         * Only increment address AFTER first word is written
		                         * first_word_written flag is set after first write completes
                                         */
		                        if(first_word_written)
			                        next_UART_SRAM_ADDR = UART_SRAM_ADDR + 1;
                                end
                        end else begin
		                next_state = DONE;
	                end
                end
	        DONE:
	                next_state = IDLE;
	        default:
	                next_state = IDLE;
        endcase
end

assign start = UART_load_en;

endmodule