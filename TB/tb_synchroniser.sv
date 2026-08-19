`timescale 1ns / 1ps
///////////////////////////////////////////////////////////////////////////////////////////////////
// Engineer: Shashank Tiwari, Samyak Nidhi, Rohith Suju
// Update Date: 27.06.2026
// Module Name: tb_synchroniser.v
// Project Name: Silicon SoC kNN
// Description:
// Independent testbench for verifying synchroniser.v functionality in the design. Need to use
// post synthesis vivado timing simulation for accurate results. Decimal # delay values are used
// to simulate applying an asynchronous signal to the synchronisr.
///////////////////////////////////////////////////////////////////////////////////////////////////

module tb_synchroniser();

        localparam integer REFRESH_CYCLES = 1_000_000;

        reg        clk;
        reg        resetn;
        reg        load_en_async;
        reg  [1:0] mode_sel_async;

        wire       load_en;
        wire [1:0] mode_sel;

synchroniser #(
        .REFRESH_CYCLES(REFRESH_CYCLES)
) uut (
        .clk(clk),
        .resetn(resetn),
        .load_en_async(load_en_async),
        .mode_sel_async(mode_sel_async),
        .load_en(load_en),
        .mode_sel(mode_sel)
);

        integer pass_count = 0;
        integer cycle_count;
        integer success;

        task apply_reset ();
        begin
                load_en_async = 1'b0;
                mode_sel_async = 2'b00;
                resetn = 1'b0;
                #20;
                resetn = 1'b1;
                #1000;
        end
        endtask

        task apply_async_load_en (input value, input real delay);
        begin
                #delay;
                load_en_async = value;
        end
        endtask

        task deassert_async_load_en ();
        begin
                #100;
                load_en_async = 1'b0;
        end
        endtask

        task apply_async_mode_sel (input [1:0] value, input real delay);
        begin
                #delay;
                mode_sel_async = value;
        end
        endtask

        initial
        begin
                clk = 1'b0;
                forever #5 clk = ~clk; // 100 MHz clock -> 10ns period
        end

        initial
        begin
                //--------//
                // TEST 1 //
                //--------//
                apply_reset();

                @(posedge clk);
                apply_async_load_en(1'b1, 3.42);

                cycle_count = 0;
                success = 0;

                while (cycle_count < 5 && !success)
                begin
                        @(posedge clk);
                        cycle_count = cycle_count + 1;

                        if (load_en === 1'b1)
                                success = 1;
                end

                deassert_async_load_en();

                if (success == 0)
                        $display("Test FAILED: load_en did not synchronise to 1");
                else
                begin
                        $display("Test PASSED: load_en synchronised to 1");
                        pass_count = pass_count + 1;
                end

                #1000;

                @(posedge clk);
                apply_async_mode_sel(2'b10, 7.89);

                repeat (5) @(posedge clk);
                if (mode_sel !== 2'b10)
                        $display("Test FAILED: mode_sel did not synchronise to 2'b10");
                else
                begin
                        $display("Test PASSED: mode_sel synchronised to 2'b10");
                        pass_count = pass_count + 1;
                end

                #1000;

                //--------//
                // TEST 2 //
                //--------//
                apply_reset();

                @(posedge clk);
                apply_async_load_en(1'b1, 2.15);

                cycle_count = 0;
                success = 0;

                while (cycle_count < 5 && !success)
                begin
                        @(posedge clk);
                        cycle_count = cycle_count + 1;

                        if (load_en === 1'b1)
                                success = 1;
                end

                deassert_async_load_en();

                if (success == 0)
                        $display("Test FAILED: load_en did not synchronise to 1");
                else
                begin
                        $display("Test PASSED: load_en synchronised to 1");
                        pass_count = pass_count + 1;
                end

                #1000;

                @(posedge clk);
                apply_async_mode_sel(2'b01, 4.67);
                repeat (5) @(posedge clk);
                if (mode_sel !== 2'b01)
                        $display("Test FAILED: mode_sel did not synchronise to 2'b01");
                else
                begin
                        $display("Test PASSED: mode_sel synchronised to 2'b01");
                        pass_count = pass_count + 1;
                end

                #1000;

                if(pass_count == 4)
                        $display("All tests PASSED");
                else
                        $display("%d tests PASSED, %d tests FAILED", pass_count, 4-pass_count);

                $finish;
        end

endmodule