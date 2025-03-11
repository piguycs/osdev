const riscv = @import("../riscv/riscv.zig");
const writer = @import("../utils/writer.zig");
const memory = @import("../memory.zig");

const KAlloc = memory.KAlloc;
const println = writer.println;
const panic = writer.panic;
const ct_assert = writer.ct_assert;

pub const PAGE_SIZE = 4096;
// max for sv39 which only uses 39 bits
pub const MAX_VADDR = 1 << 39;

pub var kernel_pagetable: u64 = undefined;

var global: *KAlloc = undefined;

///this needs to be run once on the main hart
pub fn init(kalloc: *KAlloc) !void {
    global = kalloc; // so kvminithart can also use it

    const page = kalloc.alloc();
    println("kernel page allocated at 0x{x}", .{kernel_pagetable});

    kernel_pagetable = @intFromPtr(page.ptr);
    @memset(page, 0);

    try map(page, 0x10000000, 0x10000000, PAGE_SIZE);
}

///kpgtbl: kernel page table
///vaddr: virtual address
pub fn walk(kpgtbl: u64, vaddr: u64) u64 {
    if (vaddr >= MAX_VADDR) {
        panic("virtual address: {x} exceeds max: {x}", .{ vaddr, MAX_VADDR }, @src());
    }

    const page_table: [*]u64 = @ptrFromInt(kpgtbl);

    var level: u8 = 2;
    while (level > 0) : (level -= 1) {
        _ = page_table;
        // todo
    }

    // AAAAAAAAAAAAAAAAAAAAAAAAAAA
    return 123;
}

///map a virtual address to a physical address
///pretty much copied from xv6
///might support mega pages and giga pages
pub fn map(kpgtbl: []const u8, virtualAddr: u64, physicalAddr: u64, size: u64) !void {
    println("virtual address is 0x{x}", .{virtualAddr});
    println("physical address is 0x{x}", .{physicalAddr});
    println("size is {d}", .{size});

    _ = kpgtbl;
}

///this needs to be run once per hart
pub fn inithart() void {
    riscv.sfence_vma(); // wait for any previous writes to the page table memory to finish.
    defer riscv.sfence_vma(); // flush stale entries from the TLB.

    riscv.set_satp(.Sv39, kernel_pagetable);
}
