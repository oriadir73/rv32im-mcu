#!/usr/bin/env python3
"""Lockstep ISA check of the MCU's single-cycle core vs the ISS (same programs as Lab5 + div tests)."""
import os, subprocess, sys, shutil, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from iss import ISS, read_hex
HERE = os.path.dirname(os.path.abspath(__file__))
rtl = sys.argv[1]; pattern = sys.argv[2] if len(sys.argv) > 2 else ''
tests = sorted(t for t in os.listdir(os.path.join(HERE, 'tests')) if t.startswith(('t', 'seat', 'd_', 'r_', 'm_')) and pattern in t)
results = {}
for t in tests:
    td = os.path.join(HERE, 'tests', t)
    it, dt = read_hex(f'{td}/ITCM.h', 2048), read_hex(f'{td}/DTCM.h', 2048)
    iss = ISS(it, dt, mul16=True); iss.run()
    gold = [(k, a, v) for k, a, v, _ in iss.trace]
    run = os.path.join(HERE, 'runs', 'mcu_' + os.path.basename(rtl), t); os.makedirs(run, exist_ok=True)
    for f in ('ITCM.h', 'DTCM.h'): shutil.copy(f'{td}/{f}', run)
    if os.path.exists(f'{run}/stim.txt'): os.remove(f'{run}/stim.txt')
    maxc = iss.count * 3 + sum(v for k, v in iss.ops.items() if k.startswith(('div', 'rem'))) * 40 + 200
    subprocess.run(['ghdl', '-r', '--std=08', '-fsynopsys', '-frelaxed', f'-P{HERE}/simlib',
                    f'--workdir={os.path.join(HERE, rtl)}', 'tb_mcu', f'-gMAXCYC={maxc}', '--ieee-asserts=disable'],
                   cwd=run, capture_output=True)
    com = []
    for line in open(f'{run}/commits.log'):
        k, cyc, a, v = line.split()
        if k in ('R', 'W'): com.append((k, int(a), int(v, 16), int(cyc)))
    bad = None
    for i, g in enumerate(gold):
        if i >= len(com) or com[i][:3] != g: bad = i; break
    if bad is None and len(com) > len(gold): bad = len(gold)
    dout = read_hex(f'{run}/dtcm_out.h', 2048)
    dbad = sum(1 for i in range(2048) if dout[i] != iss.dmem[i] & 0xFFFFFFFF)
    r = dict(instr=iss.count, PASS=bad is None and dbad == 0, dtcm_mismatch=dbad, ops=iss.ops)
    if bad is not None:
        g = iss.trace[bad] if bad < len(gold) else None; c = com[bad] if bad < len(com) else None
        r['detail'] = dict(gold=(g[0], g[1], f'{g[2]:08x}', f'pc={g[3]:#x}') if g else None,
                           rtl=(c[0], c[1], f'{c[2]:08x}', f'cyc={c[3]}') if c else None)
    results[t] = r
    print(f"{t:12s} {'PASS' if r['PASS'] else 'FAIL'} instr={iss.count:5d} dtcm_mismatch={dbad}" + ('' if r['PASS'] else f"  {r['detail']}"))
json.dump(results, open(os.path.join(HERE, f'results_mcu_{os.path.basename(rtl)}.json'), 'w'), indent=1)
