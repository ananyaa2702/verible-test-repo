`timescale 1ns / 1ps

///////////////////////////////////////////////////////////////////////////////////////////////////
// Engineer: Rakesh Patil, Shashank Tiwari, Samyak Nidhi
// Update Date: 09.04.2026
// Module Name: reset_synch.v
// Project Name: Silicon SoC kNN
// Description:
// This module synchronises the master reset signal coming from the outsside world which is asynchronous
// to the core clock domain. It ensures that the reset signal is properly synchronized to avoid
// metastability issues in the core logic. The module has an option to chose from two different
// synchronizer depths (2 or 3 flip-flops) using generate statements. The synchronized reset signal is
// then used to reset the core logic when asserted. The synchronized reset signal is active low and
// is used to reset the core logic when asserted.
///////////////////////////////////////////////////////////////////////////////////////////////////

module reset_synch
#(
        parameter FF_COUNT = 5
) (
        input wire clk,
        input wire master_resetn,
        output wire resetn
);

reg q1;
reg q2;
reg q3;
reg q4;
reg q5;

generate
        case(FF_COUNT)
                2:
                begin : FF2_reset_synchroniser
                        always@(posedge clk or negedge master_resetn)
                        begin
                                if (!master_resetn)
                                begin
                                        q1 <= 1'b0;
                                        q2 <= 1'b0;
                                end
                                else
                                begin
                                        q1 <= 1'b1;
                                        q2 <= q1;
                                end
                        end
                        assign resetn = q2;
                end

                3:
                begin : FF3_reset_synchroniser
                        always@(posedge clk or negedge master_resetn)
                        begin
                                if (!master_resetn)
                                begin
                                        q1 <= 1'b0;
                                        q2 <= 1'b0;
                                        q3 <= 1'b0;
                                end
                                else
                                begin
                                        q1 <= 1'b1;
                                        q2 <= q1;
                                        q3 <= q2;
                                end
                        end
                        assign resetn = q3;
                end

                4:
                begin : FF4_reset_synchroniser
                        always@(posedge clk or negedge master_resetn)
                        begin
                                if (!master_resetn)
                                begin
                                        q1 <= 1'b0;
                                        q2 <= 1'b0;
                                        q3 <= 1'b0;
                                        q4 <= 1'b0;
                                end
                                else
                                begin
                                        q1 <= 1'b1;
                                        q2 <= q1;
                                        q3 <= q2;
                                        q4 <= q3;
                                end
                        end
                        assign resetn = q4;
                end

                5:
                begin : FF5_reset_synchroniser
                        always@(posedge clk or negedge master_resetn)
                        begin
                                if (!master_resetn)
                                begin
                                        q1 <= 1'b0;
                                        q2 <= 1'b0;
                                        q3 <= 1'b0;
                                        q4 <= 1'b0;
                                        q5 <= 1'b0;
                                end
                                else
                                begin
                                        q1 <= 1'b1;
                                        q2 <= q1;
                                        q3 <= q2;
                                        q4 <= q3;
                                        q5 <= q4;
                                end
                        end
                        assign resetn = q5;
                end

                default:
                begin : Default_FF_reset_synchroniser
                        always@(posedge clk or negedge master_resetn)
                        begin
                                if (!master_resetn)
                                begin
                                        q1 <= 1'b0;
                                        q2 <= 1'b0;
                                end
                                else
                                begin
                                        q1 <= 1'b1;
                                        q2 <= q1;
                                end
                        end
                        assign resetn = q2;
                end
        endcase
endgenerate

endmodule
