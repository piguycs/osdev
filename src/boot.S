.section .text.boot
.global _start
.global _second_start
_start:
    la sp, _stack
    li a1, 1024*4
    addi a0, a0, 2
    mul a1, a1, a0
    add sp, sp, a1

    la t0, _trap
    csrw stvec, t0

    # jump to the kernel
    j kmain

_trap:
    j trap

_second_start:
    la sp, _stack
    li a1, 1024*4
    addi a0, a0, 1
    mul a1, a0, a1
    add sp, sp, a1
    
    la t0, _trap
    csrw stvec, t0
    
    j secondary
