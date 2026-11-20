#!/usr/bin/env python3
"""Copy ../rtl into build/ with the simulation-only edits used by the harness (the RTL itself is untouched):
  * G_MODELSIM = 1
  * clock_tree ModelSim branch models the PLL ratio: DIVCLK = base, MCLK = SMCLK = base/4
    (the divider handshake needs DIVCLK >= 4 x MCLK, as on the FPGA: 100/20 MHz)
  * IDECODE opcode choices written as literals (GHDL requires locally static choices)
  * --dtcm4k : 4 KiB TCMs, which the course-provided binaries are built for
"""
import os, sys, glob
H = os.path.dirname(os.path.abspath(__file__)); B = os.path.join(H, 'build'); os.makedirs(B, exist_ok=True)
for f in glob.glob(os.path.join(H, '..', 'rtl', '**', '*.*'), recursive=True):
    if f.lower().endswith('.vhd') and os.path.basename(f) != 'PLL.vhd':
        open(os.path.join(B, os.path.basename(f)), 'w').write(open(f).read().replace('\r', ''))
def edit(name, old, new):
    p = os.path.join(B, name); s = open(p).read(); assert old in s, (name, old[:50]); open(p, 'w').write(s.replace(old, new))
edit('cond_compilation_package.vhd', 'constant G_MODELSIM\t\t\t\t\t: integer\t:= 0;', 'constant G_MODELSIM\t\t\t\t\t: integer\t:= 1;')
if '--dtcm4k' in sys.argv:
    for a, b in [('M9K_TCM8KiB_ADDRWIDTH;', 'M9K_TCM4KiB_ADDRWIDTH;'), ('M9K_TCM8KiB_WORDSNUM;', 'M9K_TCM4KiB_WORDSNUM;'),
                 ('PC_WIDTH_TCM8KiB;', 'PC_WIDTH_TCM4KiB;'), ('MA_WIDTH_TCM8KiB;', 'MA_WIDTH_TCM4KiB;')]:
        edit('cond_compilation_package.vhd', ':= ' + a, ':= ' + b)
for a, b in [('when INST_LW(6 DOWNTO 0),', 'when "0000011",'), ('when INST_JALR(6 DOWNTO 0),', 'when "1100111",'),
             ('when INST_LUI(6 DOWNTO 0),', 'when "0110111",')]:
    edit('IDECODE.VHD', a, b)
edit('clock_tree.vhd', """		mclk_o      <= baseclk_i;
		accelclk_o	<= baseclk_i;
		smclk_o    	<= baseclk_i;""", """		SIMCLK: block
			signal cnt_q : integer range 0 to 3 := 0;
			signal mclk_q : std_logic := '0';
		begin
			process(baseclk_i) begin
				if rising_edge(baseclk_i) then
					if cnt_q = 3 then cnt_q <= 0; else cnt_q <= cnt_q + 1; end if;
					if cnt_q = 1 then mclk_q <= '0'; elsif cnt_q = 3 then mclk_q <= '1'; end if;
				end if;
			end process;
			mclk_o <= mclk_q; accelclk_o <= baseclk_i; smclk_o <= mclk_q;
		end block;""")
print('build/ ready')
