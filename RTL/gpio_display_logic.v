`timescale 1ns / 1ps

///////////////////////////////////////////////////////////////////////////////////////////////////
// Engineer: Rakesh Patil, Shashank Tiwari, Samyak Nidhi
// Update Date: 03.04.2026
// Module Name: gpio_display_logic.v
// Project Name: Silicon SoC kNN
// Description:
// Generic GPIO output register stage.
// Latches MMIO-updated GPIO register data to the top-level GPIO output bus.
///////////////////////////////////////////////////////////////////////////////////////////////////

module gpio_display_logic (
        input wire clk,
        input wire resetn,
        input wire [9:0] gpio_reg,
        output reg [9:0] gpio_out
);

        // Register the GPIO output bus and clear it on reset.
        always @(posedge clk)
        begin
                if (!resetn)
                        gpio_out <= 10'b0;
                else
                        gpio_out <= gpio_reg;
        end

endmodule
