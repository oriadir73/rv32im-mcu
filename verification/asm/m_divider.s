.data
buf: .word 0
out: .space 256
.text
main:
    la   x20, out
    li   x1, 1000
    li   x2, 7
    divu x3, x1, x2          # 142
    remu x4, x1, x2          # same operands -> result reuse path
    add  x5, x3, x4          # dependent use right after divider
    sw   x3, 0(x20)
    sw   x4, 4(x20)
    sw   x5, 8(x20)
    li   x6, -1              # 0xFFFFFFFF (unsigned max)
    li   x7, 3
    divu x8, x6, x7
    remu x9, x6, x7
    sw   x8, 12(x20)
    sw   x9, 16(x20)
    divu x10, x1, x0         # divide by zero -> 0xFFFFFFFF
    remu x11, x1, x0         # -> dividend
    sw   x10, 20(x20)
    sw   x11, 24(x20)
    divu x12, x2, x1         # 7/1000 = 0
    remu x13, x2, x1         # 7
    sw   x12, 28(x20)
    sw   x13, 32(x20)
    li   x14, 0x80000000
    li   x15, 0x80000000
    divu x16, x14, x15       # 1
    divu x16, x16, x16       # same reg as src and dst
    sw   x16, 36(x20)
# divider inside a loop, operands change every iteration
    li   x17, 12345
    li   x18, 1
    li   x19, 10
L:  divu x21, x17, x18
    remu x22, x17, x18
    sw   x21, 40(x20)
    sw   x22, 44(x20)
    addi x18, x18, 3
    addi x19, x19, -1
    bne  x19, x0, L
# same operands twice in a row but a different op in between
    divu x23, x1, x7
    addi x24, x23, 1
    divu x25, x1, x7
    sw   x24, 48(x20)
    sw   x25, 52(x20)
    mul  x26, x2, x7
    divu x27, x26, x2
    sw   x27, 56(x20)
end: beq x0, x0, end
