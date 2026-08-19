`timescale 1ns / 1ps
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Engineer: Shashank Tiwari, Samyak Nidhi, Tanish A Shet
// Update Date: 27.03.2026
// Module Name: Boot Controller
// Project: Silicon SoC KNN
//
// Description:
// boot controller - part of the SRAM controller. Responsible for toggling control
// signals to SRAM controller wrapper and also handling core side reset.
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

module boot_controller
(
	input           clk,
	input           load_en, resetn_in, //mapped to external switch
	input           UART_load_done, FIFO_load_done, boot_load_done,
   	input [1:0]     mode_sel, //mapped to external switch
   	input           UART_load_busy,
   	input           FIFO_load_busy,
   	input           boot_load_busy,
   	output reg      resetn_core_req, //resetn_request for core to reset controller
   	output reg      boot_en, fw_load_en, UART_rx_en,FIFO_rx_en,
   	output reg      load_busy,
   	output reg      load_done
);

//-------------------------------------//
// parameter definition for FSM States //
//-------------------------------------//
parameter [2:0] IDLE = 3'b000,
		SAMPLE = 3'b001,
		FIFO_LOAD = 3'b010,
		UART_LOAD = 3'b011,
		RST_RELEASE = 3'b100;

//-------------------------------//
// Intermediate internal signals //
//-------------------------------//
reg fw_load_done;
wire fw_load_done_next;
reg load_done_latch;
reg [3:0] data_delay;
reg [3:0] data_delay_next;

//-----------------//
// state registers //
//-----------------//
reg [2:0] state, next_state;

//------------------------------------------------//
// Intermediate Signals for load busy/done status //
//------------------------------------------------//
wire busy_any;
wire done_any;

/*
 * State register and fw_load_done tracking.
 * Keeps a sticky "done" indication until a new load request arrives.
 */
always @ (posedge clk)
begin
	if(!resetn_in)
        begin
		state <= IDLE;
		fw_load_done <=0;
    	end
        else
        begin
		// clear done when a new load is requested from IDLE
		if (state == IDLE && load_en)
	    		fw_load_done <= 1'b0;
		else
			// latch done high until next load/reset
	    		fw_load_done <= fw_load_done_next;
		state <= next_state;
    	end
end

/*
 * Output register bank.
 * Drives the mux selects and reset request based on the active FSM state.
 */
always @ (posedge clk)
begin
	if(!resetn_in)
        begin
		resetn_core_req <= 0;
		fw_load_en <= 0;
		boot_en <= 0;
		UART_rx_en <= 0;
		FIFO_rx_en <= 0;
		data_delay <= 0;
    	end
        else
        begin
		data_delay <= data_delay_next;
		case(state)
	    		IDLE:
                        begin
				resetn_core_req <= 0;
				if(load_en & !fw_load_done)
		    			fw_load_en <= 1;
	    		end
	    		SAMPLE:
                        begin
				if(mode_sel == 2'b00)
		    			boot_en <= 1;
				else
		    			boot_en <=0;
	    		end
	    		FIFO_LOAD:
                        begin
				FIFO_rx_en <= 1;
				//if(fw_load_done_next)
		    			//fw_load_en <= 0;
	    		end
	    		UART_LOAD:
                        begin
				UART_rx_en <= 1;
				//if(fw_load_done_next)
		    			//fw_load_en <= 0;
	    		end
	    		RST_RELEASE:
                        begin
				resetn_core_req <= 1;
				if (fw_load_done)
                                begin
					if(data_delay == 4'b0011) //delay of 8 cycles
					begin
						fw_load_en <= 0;
		    				boot_en <= 0;
		    				FIFO_rx_en <= 0;
		    				UART_rx_en <= 0;
					end
					else
					begin
						fw_load_en <= 1;
		    				//boot_en <= 1;  //are these needed
		    				//FIFO_rx_en <= 1;
		    				//UART_rx_en <= 1;
					end
				end
	    		end
	    		default:
                        begin
				resetn_core_req <= 0;
				fw_load_en <= 0;
				boot_en <= 0;
				UART_rx_en <= 0;
				FIFO_rx_en <= 0;
				data_delay <= 0;
			end
		endcase
    	end
end

always @ (*)
begin
	if(!resetn_in)
		data_delay_next = 4'b0000;
	else if(state != RST_RELEASE)
		data_delay_next = 4'b0000;
	else if(state == RST_RELEASE && fw_load_done)
		if( data_delay < 4'b0011)
			data_delay_next = data_delay + 4'b0001;
		else
			data_delay_next = data_delay;
	else
		data_delay_next = data_delay;
end

/*
 * Busy/done reporting.
 * Latches load_busy directly and stretches load_done as a status flag.
 */
always @(posedge clk)
begin
        if (!resetn_in)
        begin
	        load_busy <= 1'b0;
	        load_done <= 1'b0;
	        load_done_latch <= 1'b0;
        end
        else
        begin
	        load_busy <= busy_any;

	        // latch load_done high on any done pulse, clear on new load start
	        if (state == IDLE && load_en)
	                load_done_latch <= 1'b0;
	        else if (done_any)
	                load_done_latch <= 1'b1;
                else
                        load_done_latch <= load_done_latch; // hold value

	        load_done <= load_done_latch;
        end
end

/*
 * Next-state decoder.
 * Pure combinational logic deciding the FSM transitions from inputs and mode_sel.
 */
always @ (*)
begin
	next_state = state;
    	case(state)
		IDLE:
                begin
	    		if(load_en & !fw_load_done_next)
				next_state = SAMPLE;
			else
				next_state = IDLE;
		end
		SAMPLE:
                begin
	    		case(mode_sel)
				2'b00:
					next_state = RST_RELEASE;
				2'b01:
					next_state = FIFO_LOAD;
				2'b10:
					next_state = UART_LOAD;
				default:
					next_state = SAMPLE;
	    		endcase
		end
		FIFO_LOAD:
                begin
	    		if(fw_load_done_next)
				next_state = RST_RELEASE;
			else
				next_state = FIFO_LOAD;
		end
		UART_LOAD:
                begin
	    		if(fw_load_done_next)
				next_state = RST_RELEASE;
			else
				next_state = UART_LOAD;
		end
		RST_RELEASE:
                begin
	    		if(fw_load_done_next && data_delay == 4'b0011)
				next_state = IDLE;
			else
				next_state = RST_RELEASE;
		end
		default:
                begin
			next_state = IDLE;
		end
	endcase
end

assign busy_any = UART_load_busy | FIFO_load_busy | boot_load_busy;

assign done_any = fw_load_done_next;

assign fw_load_done_next = UART_load_done | FIFO_load_done | boot_load_done;

endmodule
