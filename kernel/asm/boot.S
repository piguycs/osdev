.section .text.boot
.global _start

# opensbi halt all cores except one. this core will be used to call the
# following bit of code. this core shall start all the other cores and
# initialise them with their own stack
_start:
    jal setup_stack

    la t0, kernelvec
    csrw stvec, t0

    # we store the value of hartid, so it can be retrieved later
    mv tp, a0

    # when we call start, two parameters are passed
    # - a0: hartid - set by OpenSBI
    # - a1: fdt header ptr - set by OpenSBI (might be useful later)
    call start

# stack0 -> | 0 | 1 | <- stack pointer
# 0: offset
# 1: stack (4KB)
# sp = stack0 + 4096 * (hartid + 1)
setup_stack:
    # the base of the stack region
    # stack0 is defined in src/kernel.zig
    la sp, stack0
    # 4096KB of stack per thread
    li t1, 4096
    # a thread is always started with hartid in a0 (when using OpenSBI)
    mul t1, t1, a0
    # we add the computed offset to the stack pointer
    add sp, sp, t1
    ret
