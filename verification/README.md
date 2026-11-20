# Automated verification (GHDL + Python)

Runs the microcontroller in GHDL: instruction-by-instruction checks against a Python RISC-V model, system tests of
the GPIO / interrupt applications, an interrupt stress test, and functional coverage.

## Requirements (Linux or WSL on Windows)
* GHDL ≥ 3.0 (VHDL-2008)
* Python 3
* RISC-V binutils: `riscv64-unknown-elf-as / ld / objcopy / objdump`

Ubuntu / WSL: `sudo apt install ghdl python3 binutils-riscv64-unknown-elf`

## Run
```bash
./run.sh 300
# with the course GPIO / interrupt applications (folder with GPIO/, Interrupt-based IO/):
COURSE_APPS="/path/to/Benchmark apps" ./run.sh 300
```

## Files
| file | what it does |
|---|---|
| `run.sh` | one command for the whole flow |
| `prepare_sim.py` | copies `../rtl` into `build/` with the simulation settings: ModelSim mode, PLL clock ratio model (DIVCLK = 4× MCLK), 4 KiB TCMs |
| `tb_mcu.vhd` | board-level GHDL testbench: drives KEY / SW from a stimulus file, logs register / memory / I/O writes, LEDR / HEX / PWM |
| `simlib/altera_mf_sim.vhd` | simulation model of the Intel `altsyncram` memory |
| `iss.py` | Python RISC-V instruction-set simulator, the reference model |
| `build_prog.py` | assembles a `.s` program into `ITCM.h` / `DTCM.h` memory images |
| `gen_tests.py` | writes a directed test and N random programs into `tests/` |
| `run_mcu_isa.py` | runs the programs and compares the core with `iss.py`, instruction by instruction |
| `mcu_sys.py` | runs the GPIO / interrupt applications and checks LEDR, HEX, timer periods, PWM duty and the interrupt protocol |
| `sys_intdiv.py` | stress test: interrupts at every point of a divide loop |
| `coverage_mcu.py` | instruction, I/O-register and interrupt / timer / divider coverage |
| `asm/m_divider.s`, `asm/m_intdiv.s` | divider test and interrupt-during-divide test |

Generated folders (`build/`, `tests/`, `systests/`, `runs/`) are not part of the repository.
