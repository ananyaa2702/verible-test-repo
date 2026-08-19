## Maintainers:
#### Shashank Tiwari - https://github.com/Shashank-T1wari
#### Rohith Suju - https://github.com/roh1th-s
#### Samyak Nidhi - https://github.com/Samyaknidhi

## 1. Setting up the repo
### 1. Creating the build_config.yaml file
The __*[build_config.yaml](scripts/build_config.yaml)*__ file serves as the "file-list" containing all these sources needed to build the Vivado project:

- /RTL
- /TB
- /simdata

simdata includes all the .memh in __*memh_files*__, __*flash_memory_files*__ folder.

This file would be used by the __*[vivado_proj_build.tcl](scripts/vivado_setup/vivado_proj_build.tcl)*__ script to create the vivado project.

the tcl script also adds these settings to the vivado project:
- Generates to BRAM IPs with size required for the design (Refer __*[here](docs/configurations/configurations.md#vivado-bram-ips-configuration)*__ for more details).
- Sets the `global_defines.v` and `uart_defines.v` files as __Global Include__ in the vivado project.
- Disables timing checks in the vivado project

To begin with, first clone the repo to your local machine:

```bash
git clone <repo-url>
```

Once this repo has been cloned, go to the repo root (open a terminal in the repo root folder) and run the following commands:

```bash
cd scripts
chmod +x gen_build_config.sh
./gen_build_config.sh
cd ..
```
Now verify that the build_config.yaml file has been generated in the scripts folder.

### 2. Creating a vivado project
Once the build_config.yaml file is ready, open Vivado (GUI) and use the Tcl console.

Run the following commands in the __Vivado Tcl console__ (same order):

```bash
cd <repo-root>/scripts/vivado_setup/
pwd
source vivado_proj_build.tcl
cd ..
cd ..
vivado_project_build vivado scripts/build_config.yaml
```

This creates the project named __"vivado"__ under the repo-local __vivado/__ folder.

Expected output path:

```bash
<repo-root>/vivado/vivado.xpr
```

__NOTE:__ Keep the name of the vivado project as __"vivado"__ only.

As this already exists as a gitignore file, it will not be pushed to the remote repo.

## 2. Git Update Policy

Refer to __*[POLICY.md](docs/POLICY.md)*__ on how project and updates is to be maintained and how untested or unverified features are safely to be added to the repo without breaking the main integration branch.

## 3. Coding Style and File Structure

Refer to __*[coding-style.md](docs/Coding-Style/coding-style.md)*__ for the coding style guidelines to be followed for this repo and the file structure to be followed for all source files (Design and tb) in this repo.

Here is the current file structure for __Design Files__ for this repo:

```bash
silicon-front-end-repo/
├── RTL/
│       ├── system.v
|       ├── #<Respective .v files called directly by system.v>
|       ├── BootRom_Wrapper/
|               ├── Bootrom_wrapper.v
|               └── #<Respective .v files called directly by Bootrom_wrapper.v>
│       ├── qflexpress_subsystem/
|               ├── qflexpress_subsystem.v
|               └── #<Respective .v files called directly by qflexpress_subsystem.v>
│       ├── soc_uart_subsystem/
|               ├── soc_uart_subsystem.v
|               ├── #<Respective .v files called directly by soc_uart_subsystem.v>
|               └── uart_top/
|                       ├── uart_top.v
|                       ├── #<Respective .v files called directly by uart_top.v>
|                       └── uart_regs/
|                               ├── uart_regs.v
|                               ├── #<Respective .v files called directly by uart_regs.v>
|                               ├── uart_transmitter/
|                                       ├── uart_transmitter.v
|                                       └── #<Respective .v files called directly by uart_transmitter.v>
|                               └── uart_receiver/
|                                       ├── uart_receiver.v
|                                       └── #<Respective .v files called directly by uart_receiver.v>
|       ├── SRAM_Controller/
|               ├── SRAM_Controller.v
|               ├── #<Respective .v files called directly by SRAM_Controller.v>
|                       └── UART_Loader_Subsystem/
|                               ├── UART_Loader_Subsystem.v
|                               ├── #<Respective .v files called directly by UART_Loader_Subsystem.v>
|                               └── uart_rx_Subsystem/
|                                       ├── uart_rx_Subsystem.v
|                                       ├── #<Respective .v files called directly by uart_rx_Subsystem.v>
|                                       └── uart_rx_fifo_wrapper/
|                                               ├── uart_rx_fifo_wrapper.v
|                                               ├── #<Respective .v files called directly by uart_rx_fifo_wrapper.v>
|                                               └── fifo/
|                                                       ├── fifo.v
|                                                       └── #<Respective .v files called directly by fifo.v>
|       ├── SRAM_Wrapper/
|               ├── SRAM_Wrapper.v
|               └── #<Respective .v files called directly by SRAM_Wrapper.v>
```

All Testbench Files stored together without any sub-folder structure.

```bash
silicon-front-end-repo/
├── TB/
│   └── #<Respective .v files for testbenches>
```

## 4. Steps to run all the different testbenches
Refer to __*[testbench-setup.md](docs/Testbench-Setup/testbench-setup.md)*__ for the exact setup order used for the main SoC flow testbenches.

## 5. Configurations
Refer to __*[configurations.md](docs/configurations/configurations.md)*__ for the different ways design can be built and tested.

## 6. ASIC Synthesis and Tapeout

Refer to __*[asic-synthesis-and-tapeout.md](docs/ASIC-Synthesis-and-Tapeout/asic-synthesis-and-tapeout.md)*__ for the steps to be followed to synthesize and use the design for tapeout.

## 7. SPRAM 10k Specifications
Refer to __*[SPRAM_10k_specifications.md](docs/SPRAM_10k_specifications/SPRAM_10k_specifications.md)*__ for the specifications of the SPRAM 10k used in this design.
