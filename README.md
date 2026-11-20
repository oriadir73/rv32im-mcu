# RV32IM Microcontroller (VHDL, FPGA)

A RISC-V microcontroller for the Intel Cyclone V (Terasic DE10-Standard board), written in VHDL-2008:
a single-cycle RV32IM core, a memory-mapped I/O bus, GPIO, a basic timer with PWM and input capture, a
vectored interrupt controller, and a multicycle divider accelerator on its own clock domain.

Built by **Ori Adir** and **Zohar Bohnik**, final project of *Advanced CPU Architecture & Hardware Accelerators Lab*
(361-1-4693, Ben-Gurion University).

## Features
| Block | Details |
|---|---|
| Core | single-cycle RV32I + `mul` (16×16) + `divu` / `remu` through the accelerator; PC hold while the divider is busy |
| Clock tree | PLL → MCLK (core), SMCLK (peripherals), DIVCLK (divider, ≥ 4× MCLK) |
| Bus | 14-bit address; DTCM below 0x2000, I/O at 0x2000–0x203F; tri-state bidirectional data bus, address decoder |
| GPIO | LEDR, HEX0–HEX5 (7-segment), SW, push-buttons KEY1–KEY3 |
| Basic Timer | periodic compare interrupt, PWM output (two modes), input capture, clock source / prescaler select |
| Interrupt controller | 4 sources (BT, KEY1–3), IE / IFG / TYPE registers, fixed priority, vector table in DTCM 0x00–0x1C |
| Interrupt entry | 2-cycle hardware sequence: clear GIE (`gp[0]`), read TYPE, save the return PC to `tp`, jump through `Mem[TYPE]`; `reti` = `jalr zero,0(tp)` restores GIE |
| Divider | unsigned restoring divider, 32 DIVCLK cycles, 2-FF synchronizers between the clock domains, result reuse for identical operands |

### I/O memory map
| Address | Register | | Address | Register |
|---|---|---|---|---|
| 0x2000 | LEDR | | 0x201C / 0x201D | BTCTL1 / BTCTL2 |
| 0x2004/05 | HEX0 / HEX1 | | 0x2020 / 0x2024 | BTCMPR0 / BTCMPR1 |
| 0x2008/09 | HEX2 / HEX3 | | 0x2028 | BTCAPR |
| 0x200C/0D | HEX4 / HEX5 | | 0x202C | IE |
| 0x2010 | SW | | 0x202D | IFG |
| 0x2014 | PB (KEY) | | 0x202E | TYPE |

## Tools and flow
| Step | Tool |
|---|---|
| Design | VHDL-2008 |
| Simulation | ModelSim (Intel FPGA edition): testbenches in `tb/` with KEY / SW stimulus |
| Software | RARS (RISC-V assembler and simulator) for the GPIO / interrupt programs |
| Synthesis and timing | Quartus Prime, Cyclone V, PLL clock tree |
| On-board validation | DE10-Standard (LEDs, 7-segment, keys, PWM on LEDR9) and Signal Tap |
| Automated verification and coverage | GHDL + Python (`verification/`) |

## Repository layout
```
rtl/              top level (RV32IMscMCU.vhd), packages, clock tree, bus interface
rtl/core/         RV32IM single-cycle core, divider, synchronizer
rtl/peripherals/  GPIO, basic timer, interrupt controller, address decoder
tb/               ModelSim testbenches
verification/     automated test flow (see verification/README.md)
docs/             project report (PDF, Hebrew) and verification summary
```

## How to use
**ModelSim:** set `G_MODELSIM := 1` in `rtl/cond_compilation_package.vhd`, compile `rtl/` (packages first),
`rtl/core/`, `rtl/peripherals/` and a testbench from `tb/`, and put the program images `ITCM.hex` / `DTCM.hex` in the
simulation directory.

**Quartus:** add all of `rtl/` to a DE10-Standard project (`G_MODELSIM := 0`, the default) and place `ITCM.hex` /
`DTCM.hex` in the project directory. KEY0 is reset.

**Automated tests (Linux / WSL):**
```bash
cd verification
./run.sh 300
```
The GPIO / interrupt system tests also need the course application programs, see
[verification/README.md](verification/README.md).

## Verification
| | result |
|---|---|
| Programs checked instruction by instruction | 311 / 313 pass (the 2 others need C startup code to place the stack) |
| GPIO and interrupt applications vs their specifications | 7 / 7 |
| 55 interrupts fired at every point of a divide loop | 55 / 55 |
| Functional coverage | 34/34 instructions, 18/18 I/O registers, 13/13 interrupt / timer / divider scenarios |

Measured in simulation: timer periods 1 → ½ → ¼ → ⅛ exactly, PWM duty 50 / 75 / 87.5 / 93.75 %.
Details: [docs/VERIFICATION.md](docs/VERIFICATION.md). Project report (Hebrew): [docs/rv32im-mcu_report.pdf](docs/rv32im-mcu_report.pdf).
