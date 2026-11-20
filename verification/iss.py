#!/usr/bin/env python3
"""Tiny RV32IM instruction-set simulator used as the golden reference model.

Memory model mirrors the lab hardware:
  * ITCM: PC is PC_BITS wide (13 bits = 8 KiB), word index = PC[12:2]
  * DTCM: word index = addr[12:2]  (higher address bits ignored, like the RTL slice)
  * word-only loads/stores (lw/sw) -- anything else raises, so we notice
Produces: commit trace (rd writes + stores), final DTCM, register file, dynamic instr count.
"""
import sys

MASK = 0xFFFFFFFF


def sx(v, bits):
    v &= (1 << bits) - 1
    return v - (1 << bits) if v >> (bits - 1) else v


def read_hex(path, n):
    words = []
    for line in open(path):
        line = line.strip()
        if line:
            words.append(int(line, 16))
    return (words + [0] * n)[:n]


class ISS:
    def __init__(self, itcm, dtcm, words=2048, pc_bits=13, io=None, mul16=False):
        self.imem, self.dmem = list(itcm), list(dtcm)
        self.words, self.pcmask = words, (1 << pc_bits) - 1
        self.x = [0] * 32
        self.pc = 0
        self.trace = []          # ('R', rd, val) / ('W', idx, val)
        self.count = 0
        self.ops = {}            # mnemonic coverage
        self.io = io             # optional callback for memory-mapped IO (MCU)
        self.mul16 = mul16       # Lab5 spec: 16x16 unsigned multiplier (four 8x8), low 32 bits

    def didx(self, a):
        return (a >> 2) & (self.words - 1)

    def wr(self, rd, v):
        v &= MASK
        if rd:
            self.x[rd] = v
            self.trace.append(('R', rd, v, self.pc))

    def step(self):
        pc = self.pc
        ins = self.imem[(pc & self.pcmask) >> 2]
        op, rd, f3 = ins & 0x7F, (ins >> 7) & 31, (ins >> 12) & 7
        rs1, rs2, f7 = (ins >> 15) & 31, (ins >> 20) & 31, ins >> 25
        a, b = self.x[rs1], self.x[rs2]
        immI = sx(ins >> 20, 12)
        immS = sx(((ins >> 25) << 5) | ((ins >> 7) & 31), 12)
        immB = sx((((ins >> 31) & 1) << 12) | (((ins >> 7) & 1) << 11) |
                  (((ins >> 25) & 0x3F) << 5) | (((ins >> 8) & 0xF) << 1), 13)
        immU = ins & 0xFFFFF000
        immJ = sx((((ins >> 31) & 1) << 20) | (((ins >> 12) & 0xFF) << 12) |
                  (((ins >> 20) & 1) << 11) | (((ins >> 21) & 0x3FF) << 1), 21)
        npc = (pc + 4) & MASK
        name = None
        if op == 0x33:
            if f7 == 1:
                sa, sb = sx(a, 32), sx(b, 32)
                name = ['mul', 'mulh', 'mulhsu', 'mulhu', 'div', 'divu', 'rem', 'remu'][f3]
                if f3 == 0: r = (a & 0xFFFF) * (b & 0xFFFF) if self.mul16 else a * b
                elif f3 == 1: r = (sa * sb) >> 32
                elif f3 == 2: r = (sa * b) >> 32
                elif f3 == 3: r = (a * b) >> 32
                elif f3 == 4: r = MASK if b == 0 else int(sa / sb) if sb else 0
                elif f3 == 5: r = MASK if b == 0 else a // b
                elif f3 == 6: r = a if b == 0 else sa - sb * int(sa / sb)
                else: r = a if b == 0 else a % b
            else:
                name = {0: 'sub' if f7 == 0x20 else 'add', 1: 'sll', 2: 'slt', 3: 'sltu', 4: 'xor',
                        5: 'sra' if f7 == 0x20 else 'srl', 6: 'or', 7: 'and'}[f3]
                r = {'add': a + b, 'sub': a - b, 'sll': a << (b & 31), 'slt': int(sx(a, 32) < sx(b, 32)),
                     'sltu': int(a < b), 'xor': a ^ b, 'srl': a >> (b & 31), 'sra': sx(a, 32) >> (b & 31),
                     'or': a | b, 'and': a & b}[name]
            self.wr(rd, r)
        elif op == 0x13:
            sh = (ins >> 20) & 31
            name = {0: 'addi', 1: 'slli', 2: 'slti', 3: 'sltiu', 4: 'xori',
                    5: 'srai' if f7 == 0x20 else 'srli', 6: 'ori', 7: 'andi'}[f3]
            r = {'addi': a + immI, 'slli': a << sh, 'slti': int(sx(a, 32) < immI), 'sltiu': int(a < (immI & MASK)),
                 'xori': a ^ (immI & MASK), 'srli': a >> sh, 'srai': sx(a, 32) >> sh, 'ori': a | (immI & MASK),
                 'andi': a & (immI & MASK)}[name]
            self.wr(rd, r)
        elif op == 0x03:
            if f3 != 2: raise RuntimeError(f'non-word load at pc={pc:#x}')
            name = 'lw'
            addr = (a + immI) & MASK
            v = self.io('r', addr, None) if self.io and self.io('is', addr, None) else self.dmem[self.didx(addr)]
            self.wr(rd, v)
        elif op == 0x23:
            if f3 != 2: raise RuntimeError(f'non-word store at pc={pc:#x}')
            name = 'sw'
            addr = (a + immS) & MASK
            if self.io and self.io('is', addr, None):
                self.io('w', addr, b)
                self.trace.append(('IO', addr, b, pc))
            else:
                self.dmem[self.didx(addr)] = b
                self.trace.append(('W', self.didx(addr), b, pc))
        elif op == 0x63:
            name = ['beq', 'bne', '?', '?', 'blt', 'bge', 'bltu', 'bgeu'][f3]
            t = {'beq': a == b, 'bne': a != b, 'blt': sx(a, 32) < sx(b, 32), 'bge': sx(a, 32) >= sx(b, 32),
                 'bltu': a < b, 'bgeu': a >= b}[name]
            if t: npc = (pc + immB) & MASK
        elif op == 0x6F:
            name = 'jal'; self.wr(rd, pc + 4); npc = (pc + immJ) & MASK
        elif op == 0x67:
            name = 'jalr'; t = (a + immI) & ~1 & MASK; self.wr(rd, pc + 4); npc = t
        elif op == 0x37:
            name = 'lui'; self.wr(rd, immU)
        elif op == 0x17:
            name = 'auipc'; self.wr(rd, pc + immU)
        else:
            raise RuntimeError(f'illegal instruction {ins:#010x} at pc={pc:#x}')
        self.ops[name] = self.ops.get(name, 0) + 1
        self.count += 1
        self.pc = npc
        return npc == pc     # self-loop => program finished

    def run(self, maxsteps=2_000_000):
        for _ in range(maxsteps):
            if self.step():
                return True
        return False


if __name__ == '__main__':
    it, dt = read_hex(sys.argv[1], 2048), read_hex(sys.argv[2], 2048)
    s = ISS(it, dt)
    print('finished' if s.run() else 'TIMEOUT', s.count, 'instructions')
