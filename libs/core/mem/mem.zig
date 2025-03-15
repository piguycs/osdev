const riscv = @import("riscv");

pub const PAGE_SIZE = riscv.PAGE_SIZE;

///simple kernel page allocator
///- freeing of memory has strict requirements
///- to be used during early stages of the kernel
pub const linear = @import("linear.zig");
