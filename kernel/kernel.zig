const std = @import("std");
const core = @import("core");

const fdt = @import("riscv/fdt.zig");
const riscv = @import("riscv/riscv.zig");
const sbi = @import("riscv/sbi.zig");
const sv39 = @import("riscv/sv39.zig");

const prompts = @import("utils/prompts.zig");
const reader = @import("utils/reader.zig");
const shell = @import("utils/shell.zig");

const memory = @import("memory.zig");
const trap = @import("trap.zig");

const panic = core.log.panic;
const prompt = prompts.prompt;
const shell_command = shell.shell_command;

const NCPU = 4;

pub const std_options = std.Options{
    .logFn = core.log.stdLogAdapter,
};
const log = std.log.scoped(.kernel);

extern const end: u8;

export var stack0: [4096 * NCPU]u8 align(16) = undefined;
var fdt_header_addr: ?*fdt.Header = null;

export fn start(hartid: u64, dtb_ptr: u64) void {
    riscv.enable_all_sie();

    if (fdt_header_addr == null) {
        fdt_header_addr = @ptrFromInt(dtb_ptr);
        if (!fdt_header_addr.?.isValid()) panic("fdt is invalid", .{}, @src());

        // enable supervisor timer interrupts
        riscv.csrw("sstatus", riscv.csrr("sstatus") | (1 << 1));

        log.debug("info: assuming main thread for hart#{any}", .{hartid});
        kmain();
    } else {
        log.debug("info: assuming second thread for hart#{any}", .{hartid});
        ksecond();
    }
}

fn start_stuf(_: []const u8) void {
    //log.info("Starting...", .{});
}

export fn kmain() noreturn {
    trap.init();

    //log.info("\nhello from kmain\n", .{});

    //log.debug("kalloc", .{});
    var kalloc = memory.KAlloc.init();
    //log.debug("done kalloc", .{});

    const memreq = [_]sv39.MemReq{
        .{
            .name = "KERNEL",
            .physicalAddr = 0x80200000,
            .virtualAddr = 0x80200000,
            .numPages = memory.pageRoundUp((@intFromPtr(&end) - 0x80200000)) / 4096,
        },
    };

    sv39.init(&kalloc, &memreq) catch |err| {
        panic("could not initialise paging: {any}", .{err}, @src());
    };
    sv39.inithart();

    const time = riscv.csrr("time");
    _ = sbi.TimeExt.set_timer(time + 10000000);

    for (0..NCPU) |id| {
        _ = sbi.HartStateManagement.hart_start(id, null);
    }

    shell.kshell();

    kwait();
}

// second stage of kmain. sets up hart specific stuff
export fn ksecond() noreturn {
    sv39.inithart();
    kwait();
}

export fn kwait() noreturn {
    while (true) {
        asm volatile ("wfi");
    }
}
