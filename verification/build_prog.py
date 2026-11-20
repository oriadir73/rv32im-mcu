#!/usr/bin/env python3
"""Assemble RARS-style RV32 assembly with GNU binutils into ITCM.h / DTCM.h
(one 32-bit hex word per line), laid out like RARS's default config
(.text at 0x0 in hardware, .data such that `la` -> auipc 0x0fc10 as in the original binaries).
usage: build_prog.py OUTDIR DATA_BASE file1.s [file2.s ...]
"""
import os, re, subprocess, sys

out, data_base, srcs = sys.argv[1], int(sys.argv[2], 0), sys.argv[3:]
os.makedirs(out, exist_ok=True)

text = []
for s in srcs:
    text += open(s, encoding='utf-8', errors='replace').read().replace('\r', '').split('\n')
fixed = []
num_line = re.compile(r'^\s*-?(0x[0-9a-fA-F]+|\d+)\s*(,\s*-?(0x[0-9a-fA-F]+|\d+)\s*)*,?\s*(#.*)?$')
for line in text:
    if num_line.match(line) and fixed and re.search(r'\.word', fixed[-1].split('#')[0]):
        prev = fixed[-1].split('#')[0].rstrip().rstrip(',')
        body = line.split('#')[0].strip().rstrip(',')
        sep = ',' if not prev.rstrip().endswith('.word') else ' '
        fixed[-1] = prev + sep + body
    else:
        fixed.append(line.replace('\t', ' '))
# a bare ".word" left with no operands is illegal in GNU as
fixed = [re.sub(r'\.word\s*,', '.word ', l) for l in fixed]
asm = os.path.join(out, 'prog.S')
open(asm, 'w').write('\n'.join(fixed) + '\n')

ld = os.path.join(out, 'link.ld')
open(ld, 'w').write(f"""SECTIONS {{ . = 0x0; .text : {{ *(.text*) }}
 . = {data_base:#x}; .data : {{ *(.data*) *(.sdata*) *(.bss*) *(.sbss*) }} }}
""")
T = 'riscv64-unknown-elf-'
obj, elf = os.path.join(out, 'prog.o'), os.path.join(out, 'prog.elf')
subprocess.run([T + 'as', '-march=rv32im', '-mabi=ilp32', '-mno-relax', '-o', obj, asm], check=True)
subprocess.run([T + 'ld', '-m', 'elf32lriscv', '--no-relax', '-T', ld, '-e', '0', '-o', elf, obj], check=True)
for sec, name in (('.text', 'ITCM.h'), ('.data', 'DTCM.h')):
    b = os.path.join(out, name + '.bin')
    subprocess.run([T + 'objcopy', '-O', 'binary', '-j', sec, elf, b], check=True)
    raw = open(b, 'rb').read()
    raw += b'\0' * (-len(raw) % 4)
    words = [int.from_bytes(raw[i:i + 4], 'little') for i in range(0, len(raw), 4)]
    open(os.path.join(out, name), 'w').write(''.join(f'{w:08x}\n' for w in (words + [0] * 1024)[:max(1024, len(words))]))
    os.remove(b)
dis = subprocess.run([T + 'objdump', '-d', '-M', 'no-aliases', elf], capture_output=True, text=True).stdout
open(os.path.join(out, 'prog.dis'), 'w').write(dis)
print(out, 'ok')
