.section .text.boot
.global _start
.global _second_start
_start:
    la sp, _stack
    # 4096KB of stack per thread
    li a1, 1024*4
    # a thread is always started with hartid in a0 (when using OpenSBI)
    # we add one to it, as we dont wanna multiply by 0
    addi a0, a0, 1
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
