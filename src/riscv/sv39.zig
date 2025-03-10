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

pub fn map() void {}

///this needs to be run once per hart
pub fn inithart() void {
    riscv.sfence_vma(); // wait for any previous writes to the page table memory to finish.
    defer riscv.sfence_vma(); // flush stale entries from the TLB.

    riscv.set_satp(.Sv39, kernel_pagetable);
}
