# Verification — RV32IM microcontroller

## Method
1. **ModelSim (project flow):** the testbenches in `tb/` drive KEY / SW and check LEDR, HEX and the interrupt
   behavior of the GPIO and interrupt-based applications.
2. **Automated flow (GHDL + Python, `verification/`):**
   * **Instruction lockstep:** the core's committed results (register-file and data-memory writes) are compared
     with a Python RISC-V model on random, directed and divider programs.
   * **System tests:** the GPIO and interrupt applications run with KEY / SW stimulus from a file; LEDR, HEX and PWM
     are checked against each application's specification. Timer periods are scaled down so they fit in simulation time.
   * **Interrupt protocol checks** on every interrupt: Cycle 1 clears GIE (`gp[0] = 0`), Cycle 2 saves the return PC
     to `tp`, `reti` restores GIE, no nesting.
   * **Stress test:** KEY1 interrupts fired at every point of a `divu` / `remu` loop, results compared with the model.
   * The simulation models the PLL clock ratio (DIVCLK = 4× MCLK).

## Results
| test | result |
|---|---|
| Instruction lockstep, 313 programs | 311 / 313 (the 2 others are C programs that need startup code to place the stack) |
| GPIO test0–2: counters on LEDR / HEX, SW up / down / hold | pass |
| Interrupt test1: arrays on HEX, quotient / remainder on KEY3 | pass |
| Interrupt test2: KEYn → its HEX pair, timer counter, two KEYs at once | pass |
| Interrupt test3: timer period 1 → ½ → ¼ → ⅛ (9768 / 4888 / 2448 / 1224 cycles) | pass |
| Interrupt test4: PWM duty 50.00 / 75.00 / 87.50 / 93.75 % | pass |
| 55 interrupts during divides | 55 / 55 |

## Coverage
| bins | hit |
|---|---|
| instructions (RV32I + mul + divu / remu) | 34 / 34 |
| I/O registers (13 writes, 5 reads including the hardware TYPE read) | 18 / 18 |
| interrupt / timer / divider scenarios | 13 / 13 |

Scenarios: service of BT / KEY1 / KEY2 / KEY3, two flags pending at once, request held off while GIE = 0,
request deferred while the divider is busy, timer compare / PWM / capture, divider busy-hold and result reuse, reti.

## Note on memory images
The application images are built for 1024-word (4 KiB) TCMs, so the automated flow builds that configuration
(`--dtcm4k` in `verification/prepare_sim.py`).
