.data
IV:  .word main, 0, 0, 0, 0, KEY1_ISR, 0, 0
res: .space 64
.text
main:
    la   s0, res
    li   t0, 0x08            # IE: KEY1IE
    li   t6, 0x202C
    sw   t0, 0(t6)
    li   t6, 0x202D
    sw   zero, 0(t6)         # IFG = 0
    li   a0, 0
    ori  gp, gp, 1           # GIE = gp[0] = 1
    li   s1, 1000000
    li   s2, 7
    li   s3, 0
loop:
    divu t1, s1, s2
    remu t2, s1, s2
    add  s4, t1, t2
    sw   s4, 0(s0)
    sw   t1, 12(s0)
    addi s1, s1, 13
    addi s3, s3, 1
    li   t3, 0x2014
    lw   t4, 0(t3)           # read PORT_PB
    sw   t4, 4(s0)
    li   t5, 80
    bne  s3, t5, loop
    sw   a0, 8(s0)           # number of KEY1 ISR executions
end: beq x0, x0, end
KEY1_ISR:                    # uses only s5/s6 so the interrupted divide loop is undisturbed
    addi a0, a0, 1
    li   s5, 0x202D
    lw   s6, 0(s5)
    andi s6, s6, 0x37        # clear KEY1IFG (bit 3)
    sw   s6, 0(s5)
    jalr zero, 0(tp)         # reti
