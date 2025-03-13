const riscv = @import("riscv");
const core = @import("core");
const memory = @import("../memory.zig");

const KAlloc = memory.KAlloc;
const println = core.log.println;
const panic = core.log.panic;

const PTE_V: u64 = 1 << 0;
const PTE_R: u64 = 1 << 1;
const PTE_W: u64 = 1 << 2;
const PTE_X: u64 = 1 << 3;

pub const PAGE_SIZE = 4096;
pub const MAX_VADDR = 1 << 38; // 0x4000000000

var kernel_pagetable: u64 = undefined;
var global: *KAlloc = undefined;

pub const MemReq = struct {
    physicalAddr: u64,
    virtualAddr: u64,
    name: ?[]const u8 = null,
    numPages: u64 = 1,
};

///this needs to be run once on the main hart
pub fn init(kalloc: *KAlloc, memreq: []const MemReq) !void {
    global = kalloc;

    const page = kalloc.allocT(u64);
    @memset(page, 0);

    for (memreq) |req| {
        try map(page, req.physicalAddr, req.virtualAddr, req.numPages * PAGE_SIZE);
        println("map: physical: 0x{x}, virtual: 0x{x}, size: 0x{x}, name: {s}", .{
            req.physicalAddr,
            req.virtualAddr,
            req.numPages * PAGE_SIZE,
            req.name orelse "UNKNOWN",
        });
    }

    kernel_pagetable = @intFromPtr(page.ptr);
}

pub fn map(kpgtbl: []u64, physicalAddr: u64, virtualAddr: u64, size: u64) !void {
    if (virtualAddr % PAGE_SIZE != 0)
        panic("map: virtual address not aligned", .{}, @src());
    if (size % PAGE_SIZE != 0)
        panic("map: size not aligned", .{}, @src());
    if (size == 0)
        panic("map: size is zero", .{}, @src());

    var a = virtualAddr;
    const last = virtualAddr + size - PAGE_SIZE;
    var pa = physicalAddr;

    // Default permission flags - can be parameterized if needed
    const perm: u64 = PTE_R | PTE_W | PTE_X;

    while (true) {
        const pte = walk(kpgtbl, a);

        if (pte.* & PTE_V != 0)
            panic("map: remap", .{}, @src());

        pte.* = PA2PTE(pa) | perm | PTE_V;

        if (a == last)
            break;

        a += PAGE_SIZE;
        pa += PAGE_SIZE;
    }
}

pub fn walk(kpgtbl: []u64, virtualAddr: u64) *u64 {
    if (virtualAddr >= MAX_VADDR) panic("", .{}, @src());

    var pagetable = kpgtbl;

    var level: u6 = 2;
    while (level > 0) : (level -= 1) {
        const pte = &pagetable[PX(level, virtualAddr)];

        // valid bit is 1
        if (pte.* & PTE_V != 0) {
            pagetable = @as([*]u64, @ptrFromInt(PTE2PA(pte.*)))[0..512];
        } else {
            pagetable = global.allocT(u64);
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
