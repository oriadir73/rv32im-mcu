#!/usr/bin/env bash
# Verification of RV32IMscMCU.  Needs: ghdl (VHDL-2008), python3, riscv64-unknown-elf binutils.
# usage: ./run.sh [N_RANDOM=300]      optional: COURSE_APPS=<path to the course "Benchmark apps" folder>
set -euo pipefail
cd "$(dirname "$0")"
N=${1:-300}
rm -rf build && python3 prepare_sim.py --dtcm4k
(cd simlib && ghdl -a --std=08 --work=altera_mf -fsynopsys altera_mf_sim.vhd)
ORDER="cond_compilation_package.vhd const_package.vhd io_package.vhd aux_package.vhd CONTROL.VHD IFETCH.VHD IDECODE.VHD
 EXECUTE.VHD DMEMORY.VHD Multiplier.VHD Sync.VHD Divider.VHD RV32I_CORE.vhd clock_tree.vhd bus_interface.vhd address_decoder.vhd
 seven_segment.vhd port_ledr.vhd port_hex.vhd port_sw.vhd port_pb.vhd gpio.vhd basic_timer.vhd interrupt_controler.vhd
 peripherals.vhd RV32IMscMCU.vhd"
(cd build && ghdl -a --std=08 -fsynopsys -frelaxed -P../simlib --workdir=. $ORDER ../tb_mcu.vhd \
 && ghdl -e --std=08 -fsynopsys -frelaxed -P../simlib --workdir=. tb_mcu)
python3 gen_tests.py "$N"
python3 build_prog.py tests/m_divider 0x0FC10000 asm/m_divider.s > /dev/null
python3 build_prog.py systests/m_intdiv 0x0FC10000 asm/m_intdiv.s > /dev/null
python3 run_mcu_isa.py build | tee results_isa.txt
echo "ISA PASS $(grep -c ' PASS ' results_isa.txt) / $(wc -l < results_isa.txt)"
NPRESS=55 python3 sys_intdiv.py build
if [[ -n "${COURSE_APPS:-}" ]]; then python3 mcu_sys.py build; fi
python3 coverage_mcu.py
