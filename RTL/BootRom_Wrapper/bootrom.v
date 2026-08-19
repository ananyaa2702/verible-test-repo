`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Shashank Tiwari, Samyak Nidhi, Tanish A Shet, Rakesh Patil, Rohith Suju
// Last Modified: 27.06.2026
// Module Name: bootrom
// Project Name: Silicon SoC KNN
// Description: bootROM register file with simple read interface
//////////////////////////////////////////////////////////////////////////////////

module bootrom
(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [31:0] addr,  // word address from CPU
    input  wire        ce,    // Chip Enable
    output wire [31:0] dataout   // 32-bit instruction output
);


//----------------------------------//
// Intermediate internal signals
//----------------------------------//
reg [31:0] dout;

/*
 * Boot ROM lookup logic.
 * When ce is asserted, returns the instruction mapped to addr[11:0].
 * When ce is deasserted, returns a NOP value.
 */

always @(*)
begin
    if (ce)
        case (addr[11:0])
            12'h000: dout = 32'h06004117;
            12'h001: dout = 32'h00010113;
            12'h002: dout = 32'h008000ef;
            12'h003: dout = 32'h0000006f;
            12'h004: dout = 32'h06000437;
            12'h005: dout = 32'h05000fb7;
            12'h006: dout = 32'h120000ef;
            12'h007: dout = 32'h120000ef;
            12'h008: dout = 32'h180000ef;
            12'h009: dout = 32'h00a00293;
            12'h00A: dout = 32'h00542023;
            12'h00B: dout = 32'h01400293;
            12'h00C: dout = 32'h00542223;
            12'h00D: dout = 32'h00042303;
            12'h00E: dout = 32'h00030513;
            12'h00F: dout = 32'h130000ef;
            12'h010: dout = 32'h00500293;
            12'h011: dout = 32'hfff28293;
            12'h012: dout = 32'hfe029ee3;
            12'h013: dout = 32'h00442303;
            12'h014: dout = 32'h00030513;
            12'h015: dout = 32'h118000ef;
            12'h016: dout = 32'h00500293;
            12'h017: dout = 32'hfff28293;
            12'h018: dout = 32'hfe029ee3;
            12'h019: dout = 32'h00100293;
            12'h01A: dout = 32'h005fa023;
            12'h01B: dout = 32'h138000ef;
            12'h01C: dout = 32'h00300293;
            12'h01D: dout = 32'h005fa023;
            12'h01E: dout = 32'h00000993;
            12'h01F: dout = 32'h00400a13;
            12'h020: dout = 32'h00040a93;
            12'h021: dout = 32'h00000b13;
            12'h022: dout = 32'h0fe00513;
            12'h023: dout = 32'h0e0000ef;
            12'h024: dout = 32'h00098513;
            12'h025: dout = 32'h000a8593;
            12'h026: dout = 32'h000a0613;
            12'h027: dout = 32'h1bc000ef;
            12'h028: dout = 32'h000b0463;
            12'h029: dout = 32'h0380006f;
            12'h02A: dout = 32'h00042283;
            12'h02B: dout = 32'hb007b337;
            12'h02C: dout = 32'h00730313;
            12'h02D: dout = 32'h04629e63;
            12'h02E: dout = 32'h00442383;
            12'h02F: dout = 32'h00842e03;
            12'h030: dout = 32'h00c42b83;
            12'h031: dout = 32'h0023d393;
            12'h032: dout = 32'h00038a13;
            12'h033: dout = 32'h000e0a93;
            12'h034: dout = 32'h01098993;
            12'h035: dout = 32'h00100b13;
            12'h036: dout = 32'hfb9ff06f;
            12'h037: dout = 32'h000a8513;
            12'h038: dout = 32'h000a0593;
            12'h039: dout = 32'h030000ef;
            12'h03A: dout = 32'h03751463;
            12'h03B: dout = 32'h00400293;
            12'h03C: dout = 32'h005fa023;
            12'h03D: dout = 32'h0ff00513;
            12'h03E: dout = 32'h074000ef;
            12'h03F: dout = 32'h002002b7;
            12'h040: dout = 32'h00400313;
            12'h041: dout = 32'h0062a023;
            12'h042: dout = 32'h000a8293;
            12'h043: dout = 32'h00028067;
            12'h044: dout = 32'h0000006f;
            12'h045: dout = 32'h00000293;
            12'h046: dout = 32'h00058c63;
            12'h047: dout = 32'h00052303;
            12'h048: dout = 32'h006282b3;
            12'h049: dout = 32'h00450513;
            12'h04A: dout = 32'hfff58593;
            12'h04B: dout = 32'hfedff06f;
            12'h04C: dout = 32'h00028513;
            12'h04D: dout = 32'h00008067;
            12'h04E: dout = 32'h00008067;
            12'h04F: dout = 32'h030002b7;
            12'h050: dout = 32'h08000313;
            12'h051: dout = 32'h006281a3;
            12'h052: dout = 32'h00000313;
            12'h053: dout = 32'h006280a3;
            12'h054: dout = 32'h03600313;
            12'h055: dout = 32'h00628023;
            12'h056: dout = 32'h00300313;
            12'h057: dout = 32'h006281a3;
            12'h058: dout = 32'h0c600313;
            12'h059: dout = 32'h00628123;
            12'h05A: dout = 32'h00008067;
            12'h05B: dout = 32'h030002b7;
            12'h05C: dout = 32'h00c2c303;
            12'h05D: dout = 32'h02037313;
            12'h05E: dout = 32'hfe030ce3;
            12'h05F: dout = 32'h00a28023;
            12'h060: dout = 32'h00008067;
            12'h061: dout = 32'h030002b7;
            12'h062: dout = 32'h00c2c303;
            12'h063: dout = 32'h00137313;
            12'h064: dout = 32'hfe030ce3;
            12'h065: dout = 32'h00028303;
            12'h066: dout = 32'h00030513;
            12'h067: dout = 32'h00008067;
            12'h068: dout = 32'h00008067;
            12'h069: dout = 32'hffc10113;
            12'h06A: dout = 32'h00112023;
            12'h06B: dout = 32'h000012b7;
            12'h06C: dout = 32'hfa028293;
            12'h06D: dout = 32'hfff28293;
            12'h06E: dout = 32'hfe029ee3;
            12'h06F: dout = 32'h010000ef;
            12'h070: dout = 32'h00012083;
            12'h071: dout = 32'h00410113;
            12'h072: dout = 32'h00008067;
            12'h073: dout = 32'h001002b7;
            12'h074: dout = 32'h00001337;
            12'h075: dout = 32'h0ff30313;
            12'h076: dout = 32'h0062a023;
            12'h077: dout = 32'h0062a023;
            12'h078: dout = 32'h0062a023;
            12'h079: dout = 32'h0062a023;
            12'h07A: dout = 32'h0062a023;
            12'h07B: dout = 32'h0062a023;
            12'h07C: dout = 32'h00001337;
            12'h07D: dout = 32'h10030313;
            12'h07E: dout = 32'h0062a023;
            12'h07F: dout = 32'h00008067;
            12'h080: dout = 32'h001002b7;
            12'h081: dout = 32'h00001337;
            12'h082: dout = 32'h0eb30313;
            12'h083: dout = 32'h0062a023;
            12'h084: dout = 32'h00002337;
            12'h085: dout = 32'ha0030313;
            12'h086: dout = 32'h0062a023;
            12'h087: dout = 32'h0062a023;
            12'h088: dout = 32'h0062a023;
            12'h089: dout = 32'h00002337;
            12'h08A: dout = 32'haa030313;
            12'h08B: dout = 32'h0062a023;
            12'h08C: dout = 32'h00002337;
            12'h08D: dout = 32'h80030313;
            12'h08E: dout = 32'h0062a023;
            12'h08F: dout = 32'h0062a023;
            12'h090: dout = 32'h0062a023;
            12'h091: dout = 32'h0062a023;
            12'h092: dout = 32'h0062a023;
            12'h093: dout = 32'h10000313;
            12'h094: dout = 32'h0062a023;
            12'h095: dout = 32'h00008067;
            12'h096: dout = 32'h08060e63;
            12'h097: dout = 32'h001002b7;
            12'h098: dout = 32'h00001337;
            12'h099: dout = 32'h00330313;
            12'h09A: dout = 32'h0062a023;
            12'h09B: dout = 32'h00001f37;
            12'h09C: dout = 32'h01055393;
            12'h09D: dout = 32'h0ff3f393;
            12'h09E: dout = 32'h007f6333;
            12'h09F: dout = 32'h0062a023;
            12'h0A0: dout = 32'h00855393;
            12'h0A1: dout = 32'h0ff3f393;
            12'h0A2: dout = 32'h007f6333;
            12'h0A3: dout = 32'h0062a023;
            12'h0A4: dout = 32'h0ff57393;
            12'h0A5: dout = 32'h007f6333;
            12'h0A6: dout = 32'h0062a023;
            12'h0A7: dout = 32'h01e2a023;
            12'h0A8: dout = 32'h0002ae03;
            12'h0A9: dout = 32'h0ffe7e93;
            12'h0AA: dout = 32'h01e2a023;
            12'h0AB: dout = 32'h0002ae03;
            12'h0AC: dout = 32'h0ffe7e13;
            12'h0AD: dout = 32'h008e1e13;
            12'h0AE: dout = 32'h01ceeeb3;
            12'h0AF: dout = 32'h01e2a023;
            12'h0B0: dout = 32'h0002ae03;
            12'h0B1: dout = 32'h0ffe7e13;
            12'h0B2: dout = 32'h010e1e13;
            12'h0B3: dout = 32'h01ceeeb3;
            12'h0B4: dout = 32'h01e2a023;
            12'h0B5: dout = 32'h0002ae03;
            12'h0B6: dout = 32'h0ffe7e13;
            12'h0B7: dout = 32'h018e1e13;
            12'h0B8: dout = 32'h01ceeeb3;
            12'h0B9: dout = 32'h01d5a023;
            12'h0BA: dout = 32'h00458593;
            12'h0BB: dout = 32'hfff60613;
            12'h0BC: dout = 32'hfa0616e3;
            12'h0BD: dout = 32'h00001337;
            12'h0BE: dout = 32'h10030313;
            12'h0BF: dout = 32'h0062a023;
            12'h0C0: dout = 32'h00008067;
            default: dout = 32'h00000013; // RISC-V NOP
        endcase
    else
        dout = 32'h00000013; // Default to NOP when disabled
end

// Output mapping from internal ROM data register.
assign dataout = dout;

endmodule
