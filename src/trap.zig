const riscv = @import("riscv/riscv.zig");
const writer = @import("writer.zig");

const panic = writer.panic;
const println = writer.println;

extern fn hang() void;

const Cause = enum(u64) {
    Software = 0x8000000000000001,
    Timer = 0x8000000000000005,
    External = 0x8000000000000009,
    CounterOverflow = 0x8000000000000013,
};

pub fn trapinit() void {}

///# trap handler
///a trap captures all interrupts and exceptipns. If it is an exception, we
///panic. If it is an interrupt, we do whatever is appropriate
// exporting this function to make it visible on gdb
export fn trap() void {
    const sepc = riscv.csrr("sepc");
    const sstatus = riscv.csrr("sstatus");
    const scause: Cause = @enumFromInt(riscv.csrr("scause"));

    if (scause == Cause.Timer) {
        println("timer hit", .{});
        hang(); // we do not reset the interrupt reg yet
    }

    panic("sepc=0x{x} sstatus=0x{x} scause=0x{x}", .{ sepc, sstatus, @intFromEnum(scause) }, null);
}
