.section .text.boot
.global _start

_start:
    jal _setup_stack

    la t0, _trap
    csrw stvec, t0

    j kmain

.section .text.other
.global _second_start

_second_start:
    jal _setup_stack
    
    la t0, _trap
    csrw stvec, t0

    j secondary

# TODO: save the registers to memory and re-populate them
_trap:
    j trap


# _stack_start -> | 0 | 1 | <- stack pointer
# 0: offset
# 1: stack (4KB)
_setup_stack:
    # the base of the stack region
    la sp, _stack_start
    # 4096KB of stack per thread
    li t1, 1024*4
    # a thread is always started with hartid in a0 (when using OpenSBI)
    # we add one to it, as we dont wanna multiply by 0
    addi a0, a0, 1
    mul t1, t1, a0
    # we add the computed offset to the stack pointer
    add sp, sp, t1
    ret
