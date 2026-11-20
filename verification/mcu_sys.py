#!/usr/bin/env python3
"""System-level checks of RV32IMscMCU against the Benchmark-apps ReadMe specs + interrupt protocol.
usage: mcu_sys.py BUILD_DIR (e.g. build)"""
import os, sys, shutil, subprocess, json
HERE = os.path.dirname(os.path.abspath(__file__))
APPS = os.environ.get('COURSE_APPS', '')   # path to the course 'Benchmark apps' folder
rtl = sys.argv[1]
SEG = {0x40: 0, 0x79: 1, 0x24: 2, 0x30: 3, 0x19: 4, 0x12: 5, 0x02: 6, 0x78: 7, 0x00: 8, 0x10: 9,
       0x08: 10, 0x03: 11, 0x46: 12, 0x21: 13, 0x06: 14, 0x0E: 15}
SHIFT = 11      # timer periods (lui/addi constants >= 0x100000) are divided by 2**SHIFT for simulation


def rd_words(p):
    return [int(l, 16) for l in open(p) if l.strip()]


def speedup(words):
    """find `lui rd,U ; addi rd,rd,I` pairs building a large constant (timer periods) and scale them down"""
    out, found = list(words), []
    for i in range(len(words) - 1):
        a, b = words[i], words[i + 1]
        if a & 0x7F == 0x37 and b & 0x707F == 0x13:
            rd = (a >> 7) & 31
            if (b >> 7) & 31 == rd and (b >> 15) & 31 == rd:
                imm = b >> 20; imm = imm - 4096 if imm & 0x800 else imm
                c = ((a & 0xFFFFF000) + imm) & 0xFFFFFFFF
                if c >= 0x100000:
                    n = c >> SHIFT
                    hi, lo = (n + 0x800) & 0xFFFFF000, n - ((n + 0x800) & 0xFFFFF000)
                    out[i] = hi | (rd << 7) | 0x37
                    out[i + 1] = ((lo & 0xFFF) << 20) | (rd << 15) | (rd << 7) | 0x13
                    found.append((hex(c), hex(n)))
    return out, found


def run(name, app, stim, maxcyc):
    d = os.path.join(HERE, 'runs', 'sys_' + os.path.basename(rtl), name); os.makedirs(d, exist_ok=True)
    it = rd_words(f'{APPS}/{app}/bin/Hexadecimal-Text/ITCM.h')
    it, found = speedup(it)
    open(f'{d}/ITCM.h', 'w').write(''.join(f'{w:08x}\n' for w in it))
    shutil.copy(f'{APPS}/{app}/bin/Hexadecimal-Text/DTCM.h', d)
    open(f'{d}/stim.txt', 'w').write(''.join(s + '\n' for s in stim))
    subprocess.run(['ghdl', '-r', '--std=08', '-fsynopsys', '-frelaxed', f'-P{HERE}/simlib',
                    f'--workdir={os.path.join(HERE, rtl)}', 'tb_mcu', f'-gMAXCYC={maxcyc}', '--ieee-asserts=disable'],
                   cwd=d, capture_output=True)
    io = []
    for l in open(f'{d}/io.log'):
        c, led, hexs, pwm = l.split()
        h = [SEG.get(int(hexs[2 * k:2 * k + 2], 16), None) for k in range(6)]   # HEX5..HEX0
        io.append(dict(c=int(c), led=int(led, 16), hex=h, pwm=pwm == '1'))
    com = [l.split() for l in open(f'{d}/commits.log')]
    return io, com, found


def state_at(io, c):
    s = io[0]
    for e in io:
        if e['c'] > c: break
        s = e
    return s


def reg_hist(com, r):
    return [(int(x[1]), int(x[3], 16)) for x in com if x[0] == 'R' and int(x[2]) == r]


def protocol(com, cyc_end):
    """interrupt-service protocol from the design: Cycle1 clears GIE (gp<=0), Cycle2 saves return PC
    to tp, reti (jalr zero,0(tp)) sets gp<=1. No nesting; every service returns."""
    o = [(int(x[1]), int(x[2]), int(x[3], 16)) for x in com if x[0] == 'O']
    errs, depth, n = [], 0, 0
    for i, (c, r, v) in enumerate(o):
        if r == 3 and v == 0:
            if depth: errs.append(f'nested service at cycle {c}')
            depth = 1; n += 1
            if i + 1 >= len(o) or o[i + 1][1] != 4: errs.append(f'no tp save after GIE clear at {c}')
        elif r == 3 and v == 1:
            if not depth: errs.append(f'reti without service at {c}')
            depth = 0
    return n, errs


results = {}


def report(name, checks, extra=None):
    ok = all(v for _, v in checks)
    results[name] = dict(PASS=ok, checks=[(k, bool(v)) for k, v in checks], **(extra or {}))
    print(f"{name:22s} {'PASS' if ok else 'FAIL'}  " + ', '.join(f"{k}={'ok' if v else 'FAIL'}" for k, v in checks))


# ---------------- GPIO test0: count up on LEDR and every HEX ----------------
io, com, _ = run('gpio_test0', 'GPIO/test0', [], 4000)
def stable(io):
    # display state right before each LEDR update (all digits of the previous value written)
    return [a for a, b in zip(io, io[1:]) if b['led'] != a['led'] and a['c'] > 5]
vals = stable(io)
seq = [e['led'] for e in io if e['c'] > 5]
steps = [(b - a) & 0xFF for a, b in zip(seq, seq[1:]) if a != b]
report('GPIO test0', [('counts_up_by_1', len(steps) > 20 and all(s == 1 for s in steps)),
                      ('all_HEX_mirror_value', len(vals) > 20 and all(all(h == (e['led'] & 0xF) for h in e['hex']) for e in vals[1:]))])

# ---------------- GPIO test1: SW=1 up, SW=2 down, else hold ----------------
stim = ['0 SW 01', '1500 SW 02', '3000 SW 00', '4000 SW 05', '5000 SW 81']
io, com, _ = run('gpio_test1', 'GPIO/test1', stim, 6500)
def window(a, b): return [e['led'] for e in io if a < e['c'] <= b]
up, dn, hold, hold2, up2 = window(100, 1500), window(1600, 3000), window(3100, 4000), window(4100, 5000), window(5100, 6500)
d = lambda s: {(y - x) & 0xFF for x, y in zip(s, s[1:]) if x != y}
report('GPIO test1', [('SW=0x01 counts up', len(up) > 10 and d(up) == {1}), ('SW=0x02 counts down', len(dn) > 10 and d(dn) == {0xFF}),
                      ('SW=0x00 holds', len(hold) <= 1), ('SW=0x05 holds (only SW0..1 decode)', len(hold2) <= 1 or d(hold2) == {1}),
                      ('SW=0x81 counts up (SW7 ignored)', len(up2) > 5 and d(up2) == {1})])

# ---------------- GPIO test2: six-digit hex counter on HEX5..HEX0 + LEDR ----------------
stim = ['0 SW 01', '3000 SW 02', '6000 SW 00']
io, com, _ = run('gpio_test2', 'GPIO/test2', stim, 7000)
num = lambda e: None if None in e['hex'] else sum(h << (4 * (5 - k)) for k, h in enumerate(e['hex']))
# test2 writes the HEX array first and LEDR last, so the consistent point is right AFTER each LEDR update
snaps = [(b['c'], num(b), b['led']) for a, b in zip(io, io[1:]) if b['led'] != a['led'] and b['c'] > 100]
up = [n for c, n, _ in snaps if c < 3000 and n is not None]
dn = [n for c, n, _ in snaps if 3100 < c < 6000 and n is not None]
mono = lambda s, sgn: all((b - a) * sgn >= 0 for a, b in zip(s, s[1:]))
led_ok = len(snaps) > 20 and all(led == (n & 0xFF) for c, n, led in snaps[1:] if n is not None)
report('GPIO test2', [('HEX array counts up', len(set(up)) > 10 and mono(up, 1)), ('HEX array counts down', len(set(dn)) > 10 and mono(dn, -1)),
                      ('LEDR = low byte of counter', led_ok)])

# ---------------- Interrupt test2: KEYn prints a0 on its HEX pair; BT tick a0++ ----------------
def press(k, c, hold=20): return [f'{c} KEY {k} 0', f'{c + hold} KEY {k} 1']
stim = press(1, 9000) + press(2, 16000) + press(3, 23000) + press(1, 30000) + [f'34000 KEY 1 0', f'34000 KEY 3 0', f'34020 KEY 1 1', f'34020 KEY 3 1']
io, com, found = run('int_test2', 'Interrupt-based IO/test2', stim, 37000)
a0 = reg_hist(com, 10)
def a0_at(c):
    v = 0
    for cc, x in a0:
        if cc > c: break
        v = x
    return v
def pair(e, k): h = e['hex']; hi, lo = h[5 - (2 * k - 1)], h[5 - 2 * (k - 1)]; return None if None in (hi, lo) else hi * 16 + lo
checks = [('BT ticks increment a0 by 1', len(a0) >= 3 and all(b[1] - a[1] == 1 for a, b in zip(a0, a0[1:])))]
for k, c in [(1, 9000), (2, 16000), (3, 23000), (1, 30000)]:
    before, after = state_at(io, c - 1), state_at(io, c + 2000)
    want = a0_at(c + 2000) & 0xFF
    others = [j for j in (1, 2, 3) if j != k]
    checks.append((f'KEY{k}@{c}: HEX pair{k}=a0', pair(after, k) in (want, (want - 1) & 0xFF)))
    checks.append((f'KEY{k}@{c}: other pairs unchanged', all(pair(after, j) == pair(before, j) for j in others)))
n, errs = protocol(com, 37000)
checks.append((f'interrupt protocol ({n} services)', n >= 4 and not errs))
svc = [int(x[1]) for x in com if x[0] == 'O' and x[2] == '3' and x[3] == '00000000' and 34000 <= int(x[1]) < 35000]
checks.append(('KEY1+KEY3 simultaneous: both serviced, back-to-back', len(svc) == 2))
fin = state_at(io, 36900)
checks.append(('KEY1+KEY3 simultaneous: KEY3 (lower priority) served last -> pair3 updated', pair(fin, 3) in (a0_at(36900) & 0xFF, (a0_at(36900) - 1) & 0xFF)))
report('INT test2', checks, dict(timer_constants_scaled=found, protocol_errors=errs))

# ---------------- Interrupt test3: KEYn changes BT period (1/2, 1/4, 1/8) and prints a0 on pair + LEDR -------
stim = press(1, 30000) + press(2, 48000) + press(3, 62000)
io, com, found = run('int_test3', 'Interrupt-based IO/test3', stim, 75000)
a0 = reg_hist(com, 10)
def period(a, b):
    cs = [c for c, _ in a0 if a < c < b]
    gaps = [y - x for x, y in zip(cs, cs[1:])]
    return sorted(gaps)[len(gaps) // 2] if gaps else None
p0, p1, p2, p3 = period(0, 30000), period(36000, 48000), period(51000, 62000), period(64000, 75000)
ratio = lambda a, b, r: a and b and abs(a / b - r) / r < 0.1
checks = [('base period measured', p0 is not None), ('KEY1 halves period', ratio(p0, p1, 2)), ('KEY2 -> 1/4', ratio(p0, p2, 4)), ('KEY3 -> 1/8', ratio(p0, p3, 8))]
for k, c in [(1, 30000), (2, 48000), (3, 62000)]:
    after = state_at(io, c + 1500); want = a0_at(c + 1500) & 0xFF
    checks.append((f'KEY{k}: pair{k}=a0 and LEDR=a0', pair(after, k) in (want, (want - 1) & 0xFF) and after['led'] in (want, (want - 1) & 0xFF)))
n, errs = protocol(com, 75000)
checks.append((f'interrupt protocol ({n} services)', n >= 10 and not errs))
report('INT test3', checks, dict(periods=[p0, p1, p2, p3], timer_constants_scaled=found, protocol_errors=errs))

# ---------------- Interrupt test1: KEY1 arr1[i] on HEX5:4, KEY2 arr2[i] on HEX3:2, KEY3 quotient/remainder ----------
arr1, arr2 = [100, 98, 97, 96, 95, 94, 93, 92], [8, 7, 6, 5, 4, 3, 2, 1]
stim = ['0 SW 01'] + press(1, 2000) + press(2, 6000) + press(3, 10000)
io, com, found = run('int_test1', 'Interrupt-based IO/test1', stim, 40000)
after1, after2 = state_at(io, 5000), state_at(io, 9000)
quot = [(e['hex'][4] * 16 + e['hex'][5]) for e in io if e['c'] > 10000 and None not in e['hex']]
rem = [e['led'] for e in io if e['c'] > 10000]
q_ok = set(quot) - {0} and set(quot) - {0} <= {a // b for a, b in zip(arr1, arr2)}
r_ok = set(rem) <= {a % b for a, b in zip(arr1, arr2)} | {0}
n, errs = protocol(com, 40000)
report('INT test1', [('KEY1: HEX5:4 shows arr1[i]', pair(after1, 3) in arr1), ('KEY2: HEX3:2 shows arr2[i]', pair(after2, 2) in arr2),
                     ('KEY3: HEX1:0 = arr1[i]/arr2[i]', bool(q_ok)), ('KEY3: LEDR = arr1[i]%arr2[i]', r_ok),
                     (f'interrupt protocol ({n} services)', n >= 3 and not errs)],
       dict(quotients_seen=sorted(set(quot)), remainders_seen=sorted(set(rem)), protocol_errors=errs))

# ---------------- Interrupt test4: KEY2 PWM duty 50/75/87.5/93.75 % ----------------
stim = press(2, 2000) + press(2, 40000) + press(2, 78000) + press(2, 116000) + press(1, 155000) + press(3, 170000) + press(3, 200000)
io, com, found = run('int_test4', 'Interrupt-based IO/test4', stim, 240000)
def duty(a, b):
    ev = [(e['c'], e['pwm']) for e in io if a < e['c'] < b]
    rises = [i for i, (c, p) in enumerate(ev) if p and i > 0 and not ev[i - 1][1]]
    if len(rises) < 2: return None
    i0, i1 = rises[0], rises[-1]
    hi = sum(ev[j + 1][0] - ev[j][0] for j in range(i0, i1) if ev[j][1])
    return hi / (ev[i1][0] - ev[i0][0])
duties = [duty(s + 8000, s + 38000) for s in (2000, 40000, 78000, 116000)]
exp = [0.5, 0.75, 0.875, 0.9375]
n, errs = protocol(com, 240000)
checks = [(f'PWM duty after KEY2 #{i + 1} = {e * 100:.2f}%', d is not None and (abs(d - e) < 0.02 or abs((1 - d) - e) < 0.02)) for i, (d, e) in enumerate(zip(duties, exp))]
checks.append((f'interrupt protocol ({n} services)', n >= 7 and not errs))
report('INT test4', checks, dict(duties=[round(d, 4) if d else None for d in duties], protocol_errors=errs))

json.dump(results, open(os.path.join(HERE, f'results_sys_{os.path.basename(rtl)}.json'), 'w'), indent=1)
