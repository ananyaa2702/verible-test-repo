# Contributing

Thanks for contributing to this RTL project!

## Pull Requests

Before opening a PR:

- Make sure the RTL design file is written in the proper coding style format.
- Every Module file MUST have a corresponding testbench file no matter how small the module is.
- Every Design file and corresponding testbench file MUST be __Post-Synthesis Timing Simulation__ verified on Vivado.
- Avoid unrelated formatting or refactoring changes.
- Update documentation if the change affects interfaces, build flow, or usage.
- If a small bug is fixed in a already committed Design file, the corresponding testbench file MUST be updated to include a test case for the bug fix and should again pass __Post-Synthesis Timing Simulation__ Verification on Vivado.

## RTL Guidelines

- Follow the existing coding style and naming conventions.
- Use synthesizable SystemVerilog/Verilog unless a testbench-only change is intended.
- Clearly document configurable parameters and module interfaces.
- Avoid introducing vendor-specific primitives unless required.
- Be mindful of clock-domain crossings, reset behavior, timing, and inferred hardware.
- Prefer simple, deterministic RTL over unnecessarily complex implementations.

## Testing

For RTL changes, include appropriate verification such as:

- Simulation/testbench results
- Assertions or directed tests where applicable
- Synthesis results for significant changes
- Timing/resource impact if the change affects the datapath or architecture.

## Pull Request Description

Please include:

- **What changed**
- **Why it changed**
- **Any known limitations**
- **Resource/timing impact**, if relevant

Example:

```text
## Changes
- Added pipelining to the MAC unit.
- Updated the corresponding testbench.

## Testing
- Behavior Simulation: PASS
- Synthesis: PASS
- Post-Synthesis Timing Simulation: PASS

## Impact (if any)
- Fmax improved from 120 MHz to 165 MHz.
- Added 12 LUTs and 8 FFs.
```
