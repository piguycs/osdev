const fdt = @import("riscv/fdt.zig");
const riscv = @import("riscv/riscv.zig");
const sbi = @import("riscv/sbi.zig");
const sv39 = @import("riscv/sv39.zig");

const prompts = @import("utils/prompts.zig");
const reader = @import("utils/reader.zig");
const writer = @import("utils/writer.zig");
const shell = @import("utils/shell.zig");

const memory = @import("memory.zig");
const spinlock = @import("spinlock.zig");
const trap = @import("trap.zig");

const print = writer.print;
const println = writer.println;
const printchar = writer.printchar;
const panic = writer.panic;
const prompt = prompts.prompt;
const shell_command = shell.shell_command;

const std = @import("std");

const NCPU = 4;

pub const std_options = std.Options{
    .logFn = @import("core").log.stdLogAdapter,
};

extern const end: u8;

export var stack0: [4096 * NCPU]u8 align(16) = undefined;
var fdt_header_addr: ?*fdt.Header = null;

export fn start(hartid: u64, dtb_ptr: u64) void {
    std.log.info("HELLO {s}", .{"WORLD"});

    riscv.enable_all_sie();

    if (fdt_header_addr == null) {
        fdt_header_addr = @ptrFromInt(dtb_ptr);
        if (!fdt_header_addr.?.isValid()) panic("fdt is invalid", .{}, @src());

        // enable supervisor timer interrupts
        riscv.csrw("sstatus", riscv.csrr("sstatus") | (1 << 1));

        _ = hartid;
        //println("info: assuming main thread for hart#{any}", .{hartid});
        kmain();
    } else {
        //println("info: assuming second thread for hart#{any}", .{hartid});
        ksecond();
    }
}

fn start_stuf(_: []const u8) void {
    // println("Prompt got: {s}", .{input});
    println("Starting...", .{});
}

export fn kmain() noreturn {
    writer.init();
    trap.init();

    println("\nhello from kmain\n", .{});

    println("kalloc", .{});
    var kalloc = memory.KAlloc.init();
    println("/kalloc", .{});

    const memreq = [_]sv39.MemReq{
        .{
            .name = "KERNEL",
            .physicalAddr = 0x80200000,
            .virtualAddr = 0x80200000,
            .numPages = memory.pageRoundUp((@intFromPtr(&end) - 0x80200000) / 4096),
        },
    };

    sv39.init(&kalloc, &memreq) catch |err| {
        panic("could not initialise paging: {any}", .{err}, @src());
    };
    sv39.inithart();
    println("done modafuka", .{});

    const time = riscv.csrr("time");
    _ = sbi.TimeExt.set_timer(time + 10000000);

    // for (0..NCPU) |id| {
    //     _ = sbi.HartStateManagement.hart_start(id, null);
    // }

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
