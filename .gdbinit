set architecture riscv:rv64
set disassemble-next-line on
target remote :1234
symbol-file zig-out/bin/kernel
set riscv use-compressed-breakpoints yes
set confirm off
