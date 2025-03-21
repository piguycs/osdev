const std = @import("std");
const alloc = @import("alloc");
const core = @import("core");
const riscv = @import("riscv");

const sv39 = riscv.paging.sv39;

const ushell = @import("ushell.zig");
const trap = @import("trap.zig");

const fdt = riscv.fdt;
const sbi = riscv.sbi;

const panic = core.log.panic;
const pageRoundUp = core.mem.pageRoundUp;

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

    const allocator = core.mem.linear.allocator();

    const memreq = [_]sv39.MemReq{
        .{
            .name = "KERNEL_TEXT",
            .physicalAddr = 0x80200000,
            .virtualAddr = 0x80200000,
            .numPages = (pageRoundUp(@intFromPtr(&etext)) - 0x80200000) / 4096,
            .perms = sv39.PTE_R | sv39.PTE_X | sv39.PTE_U,
        },
        .{
            .name = "KERNEL_DATA",
            .physicalAddr = pageRoundUp(@intFromPtr(&etext)),
            .virtualAddr = pageRoundUp(@intFromPtr(&etext)),
            .numPages = 32000,
            .perms = sv39.PTE_R | sv39.PTE_W | sv39.PTE_U,
        },
    };

    log.info("done mapping vmem", .{});

    sv39.init(allocator, &memreq) catch |err| {
        panic("could not initialise paging: {any}", .{err}, @src());
    };
    sv39.inithart();

    const time = riscv.csrr("time");
    _ = sbi.TimeExt.set_timer(time + 10000000);

    for (0..NCPU) |id| {
        _ = sbi.HartStateManagement.hart_start(id, null);
    }

    const ushell_ptr = @intFromPtr(&ushell.ushell);
    asm volatile (
        \\csrw  sepc, %[ptr]
        \\csrr  t0, sstatus
        \\li    t1, ~(1 << 8)
        \\and   t0, t0, t1
        \\csrw  sstatus, t0
        \\sret
        :
        : [ptr] "r" (ushell_ptr),
    );

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
