const riscv = @import("riscv");

const PAGE_SIZE = riscv.PAGE_SIZE;

///simple kernel page allocator
///- freeing of memory has strict requirements
///- to be used during early stages of the kernel
const linear = @import("linear.zig");
