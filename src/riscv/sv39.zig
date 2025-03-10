const riscv = @import("../riscv/riscv.zig");
const writer = @import("../utils/writer.zig");
const memory = @import("../memory.zig");

const KAlloc = memory.KAlloc;
const println = writer.println;

pub const PAGE_SIZE = 4096;

var kernel_pagetable: u64 = undefined;

///this needs to be run once on the main hart
pub fn init(kalloc: *KAlloc) void {
    const al = kalloc.alloc();
    kernel_pagetable = @intFromPtr(al.ptr);
}

pub fn walk(_: u64) u64 {
    // AAAAAAAAAAAAAAAAAAAAAAAAAAA
    return 123;
}

///map a virtual address to a physical address
///pretty much copied from xv6
///might support mega pages and giga pages
pub fn map(virtualAddr: u64, physicalAddr: u64, size: u64) void {
    comptime if (virtualAddr % PAGE_SIZE != 0)
        @compileError("virtual address is not aligned to 4096");
    comptime if (size % PAGE_SIZE != 0) @compileError("size is not aligned to 4096");
    comptime if (size == 0) @compileError("size is 0");

    var pte: *u64 = undefined;
    var a: u64 = virtualAddr;
    var last: u64 = virtualAddr + size + PAGE_SIZE;

    while (true) {}

    _ = physicalAddr;
    _ = &pte;
    _ = &a;
    _ = &last;
}

///this needs to be run once per hart
pub fn inithart() void {
    riscv.sfence_vma(); // wait for any previous writes to the page table memory to finish.
    defer riscv.sfence_vma(); // flush stale entries from the TLB.

    riscv.set_satp(.Sv39, kernel_pagetable);
}
