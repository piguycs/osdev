const riscv = @import("riscv");

pub const PAGE_SIZE = riscv.PAGE_SIZE;

///simple kernel page allocator
///- freeing of memory has strict requirements
///- to be used during early stages of the kernel
pub const linear = @import("linear.zig");

pub fn pageRoundUp(input: u64) u64 {
    comptime if ((PAGE_SIZE & (PAGE_SIZE - 1)) != 0) {
        @compileError("PAGE_SIZE must be a power of 2");
    };

    const mask: u64 = PAGE_SIZE - 1;
    return (input + mask) & ~(mask);
}
