const riscv = @import("riscv/riscv.zig");
const sbi = @import("riscv/sbi.zig");
const fdt = @import("riscv/fdt.zig");
const println = @import("writer.zig").println;

///maximum supported CPU cores
const NCPU = 4;
pub export var stack0: [4096 * NCPU]u8 align(16) = undefined;

var fdt_header_addr: ?*fdt.Header = null;

// initialisation of hardware threads. this section is NOT unique per thread
export fn start(hartid: u64, dtb_ptr: u64) void {
    riscv.set_sie_all();

    if (fdt_header_addr == null) {
        fdt_header_addr = @ptrFromInt(dtb_ptr);

        if (@byteSwap(fdt_header_addr.?.magic) != 0xd00dfeed) {
            println("PANIC: fdt magic number does not match", .{});
            asm volatile ("j .");
        }

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
