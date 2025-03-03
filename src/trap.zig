const riscv = @import("riscv/riscv.zig");
const writer = @import("writer.zig");

const panic = writer.panic;

pub fn trapinit() void {}

///# trap handler
///a trap captures all interrupts and exceptipns. If it is an exception, we
///panic. If it is an interrupt, we do whatever is appropriate
// exporting this function to make it visible on gdb
export fn trap() void {
    const sepc = riscv.csrr("sepc");
    const sstatus = riscv.csrr("sstatus");
    const scause = riscv.csrr("scause");

    panic("sepc=0x{x} sstatus=0x{x} scause=0x{x}", .{ sepc, sstatus, scause }, null);
}
