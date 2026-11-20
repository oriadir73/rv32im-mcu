#!/usr/bin/env python3
"""Generate the directed hazard test + constrained-random programs for the pipeline.
Random programs: x20 = data base pointer (never overwritten), x1..x15 scratch, only forward
control flow (no loops) so every program terminates; ends with a self-loop."""
import os, random, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))

DIRECTED = r"""
.data
buf: .word 5, 7, -3, 0x12345678, 100, 200, 300, 400
out: .space 128
.text
main:
    la   x20, buf
    la   x21, out
# ---- dist-1/2/3 RAW through ALU (EX/MEM, MEM/WB fwd, RF write-before-read)
    addi x1, x0, 11
    addi x2, x1, 1        # dist 1 (EX/MEM)
    addi x3, x1, 2        # dist 2 (MEM/WB)
    addi x4, x1, 3        # dist 3 (RF falling-edge write)
    add  x5, x2, x3
    sub  x6, x5, x4
# ---- x0 as destination must never forward
    addi x0, x0, 55
    add  x7, x0, x0
# ---- load-use (stall) on rs1 and rs2, load->store data
    lw   x8, 4(x20)
    add  x9, x8, x1       # load-use stall (rs1)
    lw   x10, 8(x20)
    sub  x11, x1, x10     # load-use stall (rs2)
    lw   x12, 12(x20)
    sw   x12, 0(x21)      # load -> store-data
    addi x13, x1, 7
    sw   x13, 4(x21)      # store-data forward dist 1
# ---- mul-use stall + mul chains
    mul  x14, x1, x2
    add  x15, x14, x14    # mul-use stall
    mul  x16, x14, x8
    mul  x17, x16, x16
    sw   x17, 8(x21)
    lw   x18, 0(x20)
    mul  x19, x18, x13    # load -> mul
    sw   x19, 12(x21)
# ---- every ALU op incl. immediates and shifts
    lui  x22, 0xABCDE
    auipc x23, 0
    addi x24, x22, -1
    slt  x25, x10, x1
    sltu x26, x10, x1
    slti x27, x10, 0
    sltiu x28, x10, 5
    xor  x29, x22, x12
    or   x30, x29, x1
    and  x31, x30, x12
    xori x1, x1, -1
    ori  x2, x2, 0x70
    andi x3, x3, 0x0F
    sll  x4, x12, x1
    srl  x5, x12, x1
    sra  x6, x10, x2
    slli x7, x12, 31
    srli x8, x10, 1
    srai x9, x10, 1
    sw   x22, 16(x21)
    sw   x24, 20(x21)
    sw   x25, 24(x21)
    sw   x26, 28(x21)
    sw   x27, 32(x21)
    sw   x28, 36(x21)
    sw   x31, 40(x21)
    sw   x4, 44(x21)
    sw   x5, 48(x21)
    sw   x6, 52(x21)
    sw   x7, 56(x21)
    sw   x8, 60(x21)
    sw   x9, 64(x21)
# ---- taken branch whose fall-through path holds a load-use pair (stall and flush in the same cycle)
    addi x1, x0, 1
    beq  x0, x0, L1
    lw   x2, 0(x20)       # wrong path
    add  x3, x2, x2       # wrong path: load-use stall request while branch flushes
    addi x9, x0, 99       # wrong path: must never commit
    addi x9, x0, 98
L1: addi x10, x0, 2
# same with JAL
    jal  x0, L2
    lw   x2, 0(x20)
    add  x3, x2, x2
    addi x9, x0, 97
L2: addi x11, x0, 3
# same with JALR (call/ret)
    jal  x1, F1
    addi x12, x0, 4
    jal  x0, L3
F1: addi x13, x0, 5
    jalr x0, 0(x1)
    lw   x2, 0(x20)
    add  x3, x2, x2
    addi x9, x0, 96
L3:
# ---- all branch types, taken and not taken, with dependent operands
    addi x1, x0, -5
    addi x2, x0, 3
    blt  x1, x2, B1       # taken (dist-1 operand)
    addi x9, x0, 95
B1: bge  x1, x2, B2       # not taken
    bltu x1, x2, B2       # not taken (unsigned -5 big)
    bgeu x1, x2, B2       # taken
    addi x9, x0, 94
B2: bne  x1, x1, B3       # not taken
    lw   x4, 0(x20)
    beq  x4, x4, B3       # load-use into branch
    addi x9, x0, 93
B3: mul  x5, x1, x2
    bne  x5, x0, B4       # mul-use into branch
    addi x9, x0, 92
B4: sw   x9, 68(x21)
    sw   x10, 72(x21)
    sw   x11, 76(x21)
    sw   x12, 80(x21)
    sw   x13, 84(x21)
    sw   x5, 88(x21)
# back-to-back taken branches
    beq  x0, x0, C1
C1: beq  x0, x0, C2
C2: jal  x0, C3
C3: addi x14, x0, 7
    sw   x14, 92(x21)
end: beq x0, x0, end
"""

R = ['x%d' % i for i in range(1, 16)]
ALU_R = ['add', 'sub', 'sll', 'slt', 'sltu', 'xor', 'srl', 'sra', 'or', 'and', 'mul', 'mul']
ALU_I = ['addi', 'slti', 'sltiu', 'xori', 'ori', 'andi']
SH_I = ['slli', 'srli', 'srai']
BR = ['beq', 'bne', 'blt', 'bge', 'bltu', 'bgeu']


def rand_prog(seed, n=180):
    rnd = random.Random(seed)
    out = ['.data', 'buf: ' + '.word ' + ','.join(str(rnd.randint(-2**31, 2**31 - 1)) for _ in range(32)),
           '.text', 'main:', '  la x20, buf']
    for r in R:
        out.append(f'  li {r}, {rnd.randint(-2048, 2047)}')
    lbl = 0
    pending = []          # labels to place: (position, name)
    for i in range(n):
        for p in [p for p in pending if p[0] == i]:
            out.append(f'{p[1]}:')
        pending = [p for p in pending if p[0] != i]
        k = rnd.random()
        rd, a, b = rnd.choice(R), rnd.choice(R), rnd.choice(R)
        if rnd.random() < 0.08: rd = 'x0'
        off = 4 * rnd.randint(0, 31)
        if k < 0.30: out.append(f'  {rnd.choice(ALU_R)} {rd}, {a}, {b}')
        elif k < 0.45: out.append(f'  {rnd.choice(ALU_I)} {rd}, {a}, {rnd.randint(-2048, 2047)}')
        elif k < 0.50: out.append(f'  {rnd.choice(SH_I)} {rd}, {a}, {rnd.randint(0, 31)}')
        elif k < 0.53: out.append(f'  lui {rd}, {rnd.randint(0, 0xFFFFF)}')
        elif k < 0.70: out.append(f'  lw {rd}, {off}(x20)')
        elif k < 0.82: out.append(f'  sw {a}, {off}(x20)')
        elif k < 0.95:
            lbl += 1; tgt = i + rnd.randint(1, 4)
            pending.append((tgt, f'L{lbl}'))
            if rnd.random() < 0.8: out.append(f'  {rnd.choice(BR)} {a}, {b}, L{lbl}')
            else: out.append(f'  jal x0, L{lbl}')
        else:  # call/ret through jalr
            lbl += 1
            out += [f'  jal x16, F{lbl}', f'  jal x0, E{lbl}', f'F{lbl}:',
                    f'  {rnd.choice(ALU_R)} {rd}, {a}, {b}', f'  lw {rnd.choice(R)}, {off}(x20)',
                    '  jalr x0, 0(x16)', f'  lw x1, 0(x20)', f'  add x2, x1, x1', f'E{lbl}:']
    for p in pending:
        out.append(f'{p[1]}:')
    out += ['  sw x1,0(x20)'] + [f'  sw {r}, {4*j+4}(x20)' for j, r in enumerate(R[1:])]
    out.append('end: beq x0, x0, end')
    return '\n'.join(out) + '\n'


def build(name, src):
    d = os.path.join(HERE, 'tests', name); os.makedirs(d, exist_ok=True)
    s = os.path.join(d, 'src.s'); open(s, 'w').write(src)
    subprocess.run([sys.executable, os.path.join(HERE, 'build_prog.py'), d, '0x0FC10000', s],
                   check=True, capture_output=True)


if __name__ == '__main__':
    build('d_hazards', DIRECTED)
    for i in range(int(sys.argv[1]) if len(sys.argv) > 1 else 30):
        build(f'r_{i:02d}', rand_prog(1000 + i))
    print('ok')
