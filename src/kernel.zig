const fdt = @import("riscv/fdt.zig");
const riscv = @import("riscv/riscv.zig");
const sbi = @import("riscv/sbi.zig");
const memory = @import("memory.zig");
const prompts = @import("prompts.zig");
const reader = @import("reader.zig");
const shell = @import("shell.zig");
const spinlock = @import("spinlock.zig");
const trap = @import("trap.zig");
const writer = @import("writer.zig");

const print = writer.print;
const println = writer.println;
const printchar = writer.printchar;
const panic = writer.panic;
const prompt = prompts.prompt;
const shell_command = shell.shell_command;

const NCPU = 4;

export var stack0: [4096 * NCPU]u8 align(16) = undefined;
var fdt_header_addr: ?*fdt.Header = null;

export fn start(hartid: u64, dtb_ptr: u64) void {
    riscv.enable_all_sie();

    if (fdt_header_addr == null) {
        fdt_header_addr = @ptrFromInt(dtb_ptr);

        if (!fdt_header_addr.?.isValid()) panic("fdt is invalid", .{}, @src());

        riscv.csrw("sstatus", riscv.csrr("sstatus") | (1 << 1));

        println("INFO: assuming main thread for hart#{any}", .{hartid});
        kmain();
    } else {
        println("info: assuming second thread for hart#{any}", .{hartid});
        kwait();
    }
}

fn start_stuf(_: []const u8) void {
    // println("Prompt got: {s}", .{input});
    println("Starting...", .{});
}

export fn kmain() noreturn {
    println("\nhello from kmain\n", .{});

    trap.init();
    writer.init();

    const alloc = memory.KAlloc.init(4096); // 16MB of memory
    _ = alloc;

    const time = riscv.csrr("time");
    _ = sbi.TimeExt.set_timer(time + 10000000);

    for (0..NCPU) |id| {
        _ = sbi.HartStateManagement.hart_start(id, null);
    }

    //shell.kshell();

    kwait();
}

export fn kwait() noreturn {
    while (true) {
        asm volatile ("wfi");
    }
}
