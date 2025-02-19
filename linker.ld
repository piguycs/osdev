OUTPUT_ARCH("riscv")
ENTRY(_start)

SECTIONS {
    /* place our code starting from here */
    /* OpenSBI does not load our kernel on any value below this */
    . = 0x80200000;

    /* .text.init is the first section */
    .text : {
        KEEP(*(.text.boot));
        *(.text .text.*);
    }

    .rodata : ALIGN(16) {
        *(.rodata .rodata.*);
    }

    .data : ALIGN(16) {
        *(.data .data.*);
    }

    .bss : ALIGN(16) {
        _bss = .;
        *(.bss .bss.* .sbss .sbss.*);
        _bss_end = .;
    }

    _stack = .;
    . = ALIGN(16);
    . += 128 * 4 * 1024; /* 512KB: each hart gets 4096KB */
    _stack_end = .;

    . = ALIGN(4096);
    PROVIDE(_mem_start = .);
    . += 128 * 4 * 1024; /* 512KB */
    PROVIDE(_mem_end = .);
}
