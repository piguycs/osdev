const fdt = @import("riscv/fdt.zig");
const riscv = @import("riscv/riscv.zig");
const sbi = @import("riscv/sbi.zig");
const defs = @import("defs.zig");
const memory = @import("memory.zig");
const spinlock = @import("spinlock.zig");
const trap = @import("trap.zig");
const writer = @import("writer.zig");
const reader = @import("reader.zig");
const prompts = @import("prompts.zig");
const shell = @import("shell.zig");

const simple_shell = shell.shell;
const print = writer.print;
const println = writer.println;
const printchar = writer.printchar;
const panic = writer.panic;
const prompt = prompts.prompt;
const shell_command = shell.shell_command;

export var stack0: [4096 * defs.NCPU]u8 align(16) = undefined;

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
    println("hello from kmain", .{});

    trap.init();
    memory.init();
    writer.init();

    const time = riscv.csrr("time");
    _ = sbi.TimeExt.set_timer(time + 10000000);

    for (0..defs.NCPU) |id| {
        _ = sbi.HartStateManagement.hart_start(id, null);
    }

    prompt(.{
        .prompt = "Press enter to continue... ",
        .callback = start_stuf,
        .simple = true,
        .max_len = 1,
        .immediate = true,
        .show_input = false,
        .debug = false,
        .clear_line = true,
    });

    simple_shell();

    kwait();
}

export fn kwait() noreturn {
    while (true) {
        asm volatile ("wfi");
    }
}
