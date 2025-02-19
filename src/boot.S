.section .text.boot
.global _start
.global _second_start
_start:
    # load adress of _stack into the stack pointer
    la sp, _stack

    la t0, _trap
    csrw stvec, t0

    # jump to the kernel
    j kmain

_trap:
    j trap

_second_start:
    j sec
