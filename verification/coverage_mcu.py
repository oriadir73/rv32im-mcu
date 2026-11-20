#!/usr/bin/env python3
"""Light functional coverage for RV32IMscMCU: ISA, memory-mapped registers, interrupts, timer modes, divider."""
import json, os, glob
HERE = os.path.dirname(os.path.abspath(__file__))
ISA = ['lui', 'auipc', 'jal', 'jalr', 'beq', 'bne', 'blt', 'bge', 'bltu', 'bgeu', 'lw', 'sw',
       'addi', 'slti', 'sltiu', 'xori', 'ori', 'andi', 'slli', 'srli', 'srai',
       'add', 'sub', 'sll', 'slt', 'sltu', 'xor', 'srl', 'sra', 'or', 'and', 'mul', 'divu', 'remu']
WR = {'LEDR': 0x2000, 'HEX0': 0x2004, 'HEX1': 0x2005, 'HEX2': 0x2008, 'HEX3': 0x2009, 'HEX4': 0x200C, 'HEX5': 0x200D,
      'BTCTL1': 0x201C, 'BTCTL2': 0x201D, 'BTCMPR0': 0x2020, 'BTCMPR1': 0x2024, 'IE': 0x202C, 'IFG': 0x202D}
RD = {'SW': 0x2010, 'PB': 0x2014, 'IFG': 0x202D, 'BTCAPR': 0x2028, 'TYPE(hw Cycle1)': 0x202E}

ops = {}
for r in json.load(open(os.path.join(HERE, 'results_mcu_build.json'))).values():
    for k, v in r['ops'].items(): ops[k] = ops.get(k, 0) + v

wr, rd = {k: 0 for k in WR}, {k: 0 for k in RD}
bins = {k: 0 for k in ['service_BT', 'service_KEY1', 'service_KEY2', 'service_KEY3', 'two_flags_pending_at_once',
                       'request_while_GIE=0 (held off)', 'request_while_divider_busy (deferred)',
                       'timer_compare_interrupt', 'timer_PWM_output_mode', 'timer_capture_mode',
                       'divider_busy_hold', 'divider_result_reuse(no_busy)', 'reti_restores_GIE']}
runs = glob.glob(os.path.join(HERE, 'runs', 'sys_build', '*')) + [os.path.join(HERE, 'runs', 'mcu_build', 'm_divider')]  # includes m_intdiv
for d in runs:
    it = [int(l, 16) for l in open(f'{d}/ITCM.h') if l.strip()]
    dt = [int(l, 16) for l in open(f'{d}/DTCM.h') if l.strip()]
    isr_first = {}
    for k, name in [(4, 'BT'), (5, 'KEY1'), (6, 'KEY2'), (7, 'KEY3')]:
        a = dt[k] if k < len(dt) else 0
        if a // 4 < len(it): isr_first.setdefault(it[a // 4], []).append(name)
    cyc = {}
    for l in open(f'{d}/cycles.log'):
        t = l.split()
        c, ins, f, a = int(t[0]), int(t[1], 16), t[2], int(t[3])
        cyc[c] = (ins, f)
        intr, inta, gie, divb, hold, iow, ior = (x == '1' for x in f)
        if iow:
            for k, v in WR.items():
                if v == a: wr[k] += 1
        if ior:
            for k, v in RD.items():
                if v == a: rd[k] += 1
        if divb and hold: bins['divider_busy_hold'] += 1
        if divb and not inta and intr is False and gie: pass
    com = [l.split() for l in open(f'{d}/commits.log')]
    for i, x in enumerate(com):
        if x[0] == 'O' and x[2] == '4':                       # Cycle2: tp <= return PC; next cycle = ISR entry
            c = int(x[1]) + 1
            if c in cyc:
                for n in isr_first.get(cyc[c][0], []): bins['service_' + n] += 1
        if x[0] == 'O' and x[2] == '3' and x[3] == '00000001': bins['reti_restores_GIE'] += 1
        if x[0] == 'R' and False: pass
    # pending/hold-off conditions from IFG reads (value of the lw that read IFG) and timer configs
    for x in com:
        if x[0] == 'IO' and int(x[2]) == 0x201C and int(x[3], 16) & 0x40: bins['timer_PWM_output_mode'] += 1
        if x[0] == 'IO' and int(x[2]) == 0x201D and int(x[3], 16) & 0x0C: bins['timer_capture_mode'] += 1
        if x[0] == 'IO' and int(x[2]) == 0x2020: bins['timer_compare_interrupt'] += 1
    ifg_reads = [(int(t[0]), t) for t in (l.split() for l in open(f'{d}/cycles.log')) if t[2][6] == '1' and int(t[3]) == 0x202D]
    for c, _ in ifg_reads:
        for x in com:
            if x[0] == 'R' and int(x[1]) == c and bin(int(x[3], 16) & 0x3C).count('1') >= 2:
                bins['two_flags_pending_at_once'] += 1
    for l in open(f'{d}/cycles.log'):
        t = l.split(); f = t[2]
        # request seen by controller but GIE=0 (intr_o is gated by GIE, so use: KEY pressed while gie=0)
        if f[2] == '0' and (int(t[-1], 16) & 0xE) != 0xE: bins['request_while_GIE=0 (held off)'] += 1
        if f[0] == '1' and f[3] == '1': bins['request_while_divider_busy (deferred)'] += 1
# divider reuse: in m_divider, remu right after divu with same operands completes without busy
mc = [l.split() for l in open(os.path.join(HERE, 'runs', 'mcu_build', 'm_divider', 'cycles.log'))]
for a, b in zip(mc, mc[1:]):
    ia, ib = int(a[1], 16), int(b[1], 16)
    if (ia & 0xFE00707F) == 0x02005033 and (ib & 0xFE00707F) == 0x02007033 and b[2][3] == '0' and a[2][3] == '0':
        bins['divider_result_reuse(no_busy)'] += 1

isa_hit = sum(1 for k in ISA if ops.get(k))
reg_hit = sum(1 for v in wr.values() if v) + sum(1 for v in rd.values() if v)
bin_hit = sum(1 for v in bins.values() if v)
tot = len(ISA) + len(WR) + len(RD) + len(bins)
rep = dict(isa=f'{isa_hit}/{len(ISA)}', registers=f'{reg_hit}/{len(WR) + len(RD)}', system_bins=f'{bin_hit}/{len(bins)}',
           total=round(100 * (isa_hit + reg_hit + bin_hit) / tot, 1),
           missing=[k for k in ISA if not ops.get(k)] + [f'write {k}' for k, v in wr.items() if not v] +
                   [f'read {k}' for k, v in rd.items() if not v] + [k for k, v in bins.items() if not v],
           writes=wr, reads=rd, bins=bins)
json.dump(rep, open(os.path.join(HERE, 'coverage_mcu.json'), 'w'), indent=1)
print(json.dumps({k: rep[k] for k in ('isa', 'registers', 'system_bins', 'total', 'missing')}, indent=1))
print(bins)
