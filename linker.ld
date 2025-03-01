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
        *(.bss .bss.* .sbss .sbss.*);
    }

    PROVIDE(end = .);
}
