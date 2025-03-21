const riscv = @import("riscv");

const sbi = riscv.sbi;

pub export fn ushell() void {
    const hello = sbi.DebugConsoleExt.write("HELLO WORLD\n");

    if (hello.errno == .Success) {
        asm volatile ("unimp");
    }

    asm volatile ("j .");
}
