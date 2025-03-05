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
    riscv.enable_all_sie();

    if (fdt_header_addr == null) {
        fdt_header_addr = @ptrFromInt(dtb_ptr);

        if (!fdt_header_addr.?.isValid()) panic("fdt is invalid", .{}, @src());

        //disabling timer interrupts for now
        riscv.csrw("sstatus", riscv.csrr("sstatus") | (1 << 1));

        println("INFO: assuming main thread for hart#{any}", .{hartid});
        kmain();
    } else {
        //println("info: assuming second thread for hart#{any}", .{hartid});
        kwait();
    }
}

export fn kmain() noreturn {
    println("hello from kmain", .{});

    const time = riscv.csrr("time");
    _ = sbi.TimeExt.set_timer(time + 10000000);

    trap.trapinit();

    kwait();
}

export fn kwait() noreturn {
    while (true) {
        asm volatile ("wfi");
    }
}
