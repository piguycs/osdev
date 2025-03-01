const riscv = @import("riscv/riscv.zig");
const sbi = @import("riscv/sbi.zig");
const println = @import("writer.zig").println;

///maximum supported CPU cores
const NCPU = 4;
pub export var stack0: [4096 * NCPU]u8 align(16) = undefined;

// TODO: find out the specification for this and log it for debug reasons
const dtb = struct {};
var dtb_address: ?*dtb = null;

// initialisation of hardware threads. this section is NOT unique per thread
// TODO: I need some way to distinguish if this is the main hart or not
export fn start(hartid: u64, dtb_ptr: *dtb) void {
    riscv.set_sie_all();

    if (dtb_address == null) {
        dtb_address = dtb_ptr;
        println("INFO: assuming main thread for hart#{any}", .{hartid});
        kmain();
    } else {
        println("INFO: assuming second thread for hart#{any}", .{hartid});
        ksecond();
    }
}

fn kmain() noreturn {
    println("hello from kmain", .{});

    for (0..NCPU) |i| {
        // this might fail sometimes, but its fine. we bring up as many cores as
        // are available, max being NCPU
        _ = sbi.HartStateManagement.hart_start(i, null);
    }

    while (true) {
        // wait for interrupt
        asm volatile ("wfi");
    }
}

fn ksecond() noreturn {
    while (true) {
        // wait for interrupt
        asm volatile ("wfi");
    }
}
