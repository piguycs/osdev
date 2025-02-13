.section .text.boot
.global _start
_start:
    # load adress of _stack into the stack pointer
    la sp, _stack

    la t0, trap
    csrw stvec, t0

    # jump to the kernel
    j kmain
