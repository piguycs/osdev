ENTRY(_start)

/*
* _stack, _bss, _bss_end need to be declared and initialised in kmain
*/

SECTIONS {
    /* place our code starting from here */
    . = 0x80200000;

    /* .text.init is the first section */
    .text : {
        KEEP(*(.text.boot));
        *(.text .text.*);
    }

    .rodata : ALIGN(4) {
        *(.rodata .rodata.*);
    }

    .data : ALIGN(4) {
        *(.data .data.*);
    }

    .bss : ALIGN(4) {
        _bss = .;
        *(.bss .bss.* .sbss .sbss.*);
        _bss_end = .;
    }

    . = ALIGN(4);
    . += 128 * 1024; /* 128KB */
    _stack = .;
}
