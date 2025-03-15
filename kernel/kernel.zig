const std = @import("std");
const core = @import("core");
const riscv = @import("riscv");

const sv39 = @import("riscv/sv39.zig");

const memory = @import("memory.zig");
const trap = @import("trap.zig");

const fdt = riscv.fdt;
const sbi = riscv.sbi;

const panic = core.log.panic;

const NCPU = 4;

pub const std_options = std.Options{
    .logFn = core.log.stdLogAdapter,
};
const log = std.log.scoped(.kernel);

extern const etext: u8;

export var stack0: [4096 * NCPU]u8 align(16) = undefined;
var fdt_header_addr: ?*fdt.Header = null;

export fn start(hartid: u64, dtb_ptr: u64) void {
    log.info("main hart is #{any}", .{hartid});
    riscv.enable_all_sie();

    fdt_header_addr = @ptrFromInt(dtb_ptr);
    if (!fdt_header_addr.?.isValid()) panic("fdt is invalid", .{}, @src());

    // enable supervisor timer interrupts
    // riscv.csrw("sstatus", riscv.csrr("sstatus") | (1 << 1));
    asm volatile ("csrsi sstatus, 0x2"); // 1 << 1 == 0x2

    kmain();
}

export fn kmain() noreturn {
    log.info("hello from kmain", .{});

    trap.init();
    var kalloc = memory.KAlloc.init();
    core.mem.linear.init();

    var new_alloc = core.mem.linear.allocator();
    const chunk = new_alloc.alloc(u8, 2) catch {
        panic("could not alloc using newalloc", .{}, @src());
        kwait();
    };

    log.info("got chunk of size {d} at 0x{x}", .{ chunk.len, @intFromPtr(chunk.ptr) });

    const memreq = [_]sv39.MemReq{
        .{
            .name = "KERNEL_TEXT",
            .physicalAddr = 0x80200000,
            .virtualAddr = 0x80200000,
            .numPages = (memory.pageRoundUp(@intFromPtr(&etext)) - 0x80200000) / 4096,
            .perms = sv39.PTE_R | sv39.PTE_X,
        },
        .{
            .name = "KERNEL_DATA",
            .physicalAddr = memory.pageRoundUp(@intFromPtr(&etext)),
            .virtualAddr = memory.pageRoundUp(@intFromPtr(&etext)),
            .numPages = 32000,
            .perms = sv39.PTE_R | sv39.PTE_W,
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
