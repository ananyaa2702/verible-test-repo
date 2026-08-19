`timescale 1ns / 1ps

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Engineer: Rakesh Patil, Shashank Tiwari, Samyak Nidhi, Tanish A Shet
// Update Date: 10.06.2026
// Project Name: Silicon SoC kNN
// Description:
// Top-level wrapper for the qflexpress subsystem, integrating bootrom, SRAM, and boot controller.
// This module serves as the main integration point for the boot process, connecting the bootrom,
// SRAM wrapper, and boot controller together. It provides the necessary interfaces for clock, reset,
// mode selection, and control signals to facilitate the boot process from flash to core. The qflexpress_subsystem
// is designed to be flexible and modular, allowing for easy integration of different bootrom and SRAM
// implementations based on the synthesis context (FPGA vs ASIC).
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

`ifndef GLOBAL_DEFINES_V
`define GLOBAL_DEFINES_V

// Uncomment for FPGA (Vivado BRAMs)
// `define FOR_FPGA

// Uncomment for ASIC (Cadence SPRAM)
// `define FOR_ASIC

// Uncomment for SPRAM Behavioral simulation
`define FOR_SPRAM

// Uncomment for Bootrom Behavioral simulation
`define BEHAV_BOOTROM

// Uncomment for Cadence simulation
// `define CADENCE_GLS

// Uncomment for FPGA BOARD Run
// `define FOR_FPGA_BOARD

`endif // GLOBAL_DEFINES_V