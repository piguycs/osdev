const std = @import("std");
const core = @import("core");

const riscv = @import("../riscv.zig");

const println = core.log.println;
const panic = core.log.panic;

pub const PTE_V: u64 = 1 << 0;
pub const PTE_R: u64 = 1 << 1;
pub const PTE_W: u64 = 1 << 2;
pub const PTE_X: u64 = 1 << 3;
pub const PTE_U: u64 = 1 << 4;

pub const PAGE_SIZE = 4096;
pub const MAX_VADDR = 1 << 38; // 0x4000000000

const Allocator = std.mem.Allocator;

var kernel_pagetable: u64 = undefined;

const log = std.log.scoped(.sv39);

pub const MemReq = struct {
    physicalAddr: u64,
    virtualAddr: u64,
    name: ?[]const u8 = null,
    numPages: u64 = 1,
    perms: u64 = PTE_R | PTE_W | PTE_X,
};

///this needs to be run once on the main hart
pub fn init(allocator: Allocator, memreq: []const MemReq) !void {
    const page = try allocator.alloc(u64, 512);
    @memset(page, 0);

    for (memreq) |req| {
        try map(allocator, page, req.physicalAddr, req.virtualAddr, req.numPages * PAGE_SIZE, req.perms);
        log.debug("map: physical: 0x{x}, virtual: 0x{x}, size: 0x{x}, name: {s}", .{
            req.physicalAddr,
            req.virtualAddr,
            req.numPages * PAGE_SIZE,
            req.name orelse "UNKNOWN",
        });
    }

    kernel_pagetable = @intFromPtr(page.ptr);
}

pub fn map(allocator: Allocator, kpgtbl: []u64, physicalAddr: u64, virtualAddr: u64, size: u64, perms: u64) !void {
    if (virtualAddr % PAGE_SIZE != 0)
        panic("map: virtual address not aligned", .{}, @src());
    if (size % PAGE_SIZE != 0)
        panic("map: size not aligned", .{}, @src());
    if (size == 0)
        panic("map: size is zero", .{}, @src());

    var a = virtualAddr;
    const last = virtualAddr + size - PAGE_SIZE;
    var pa = physicalAddr;

    while (true) {
        const pte = walk(allocator, kpgtbl, a);

        if (pte.* & PTE_V != 0)
            panic("map: remap", .{}, @src());

        pte.* = PA2PTE(pa) | perms | PTE_V;

        if (a == last) break;

        a += PAGE_SIZE;
        pa += PAGE_SIZE;
    }
}

pub fn walk(allocator: Allocator, kpgtbl: []u64, virtualAddr: u64) *u64 {
    if (virtualAddr >= MAX_VADDR) panic("walk", .{}, @src());

    var pagetable = kpgtbl;

    var level: u6 = 2;
    while (level > 0) : (level -= 1) {
        const pte = &pagetable[PX(level, virtualAddr)];

        // valid bit is 1
        if (pte.* & PTE_V != 0) {
            pagetable = @as([*]u64, @ptrFromInt(PTE2PA(pte.*)))[0..512];
        } else {
            pagetable = allocator.alloc(u64, 512) catch |err| {
                panic("could not alloc {any}", .{err}, @src());
            };
            @memset(pagetable, 0);
            pte.* = PA2PTE(@intFromPtr(pagetable.ptr)) | PTE_V;
        }
    }

    return &pagetable[PX(0, virtualAddr)];
}

pub fn inithart() void {
    riscv.sfence_vma();
    defer riscv.sfence_vma();

    riscv.set_satp(.Sv39, kernel_pagetable);
}

inline fn PX(level: u6, va: u64) u64 {
    return va >> (12 + (9 * level)) & 0x1FF;
}
inline fn PTE2PA(pte: u64) u64 {
    return (pte >> 10) << 12;
}
inline fn PA2PTE(pa: u64) u64 {
    return (pa >> 12) << 10;
}
