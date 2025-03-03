const defs = @import("defs.zig");
const fdt = @import("riscv/fdt.zig");
const riscv = @import("riscv/riscv.zig");
const sbi = @import("riscv/sbi.zig");
const trap = @import("trap.zig");
const writer = @import("writer.zig");

const println = writer.println;
const panic = writer.panic;

export var stack0: [4096 * defs.NCPU]u8 align(16) = undefined;

var fdt_header_addr: ?*fdt.Header = null;

export fn start(hartid: u64, dtb_ptr: u64) void {
    // enable device, software and timer interrupts
    riscv.set_sie_all();

    if (fdt_header_addr == null) {
        fdt_header_addr = @ptrFromInt(dtb_ptr);

        if (!fdt_header_addr.?.isValid()) panic("fdt is invalid", .{}, @src());

        //riscv.csrw("stimecmp", riscv.csrr("time") + 1000000);

        riscv.csrw("sstatus", riscv.csrr("sstatus") | (1 << 1));

        println("INFO: assuming main thread for hart#{any}", .{hartid});
        kmain();
    } else {
        //println("info: assuming second thread for hart#{any}", .{hartid});
        kwait();
    }
}

// exporting this function to make it visible on gdb
export fn kmain() noreturn {
    println("hello from kmain", .{});

    const time = riscv.csrr("time");
    _ = sbi.TimeExt.set_timer(time + 10000000);

    for (0..defs.NCPU) |i| {
        // this might fail sometimes, but its fine. we bring up as many cores as
        // are available, max being NCPU
        _ = sbi.HartStateManagement.hart_start(i, null);
    }

    trap.trapinit();

    kwait();
}

// exporting this function to make it visible on gdb
export fn kwait() noreturn {
    while (true) {
        // wait for interrupt
        asm volatile ("wfi");
    }
}
