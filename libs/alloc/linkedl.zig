const std = @import("std");
const core = @import("core");
const riscv = @import("riscv");

const Alignment = std.mem.Alignment;
const Allocator = std.mem.Allocator;
const VTable = std.mem.Allocator.VTable;
const List = core.structs.List;
const Mutex = core.sync.Mutex;
const SpinLock = core.sync.SpinLock;

const PAGE_SIZE = riscv.PAGE_SIZE;

var singleton: ?Mutex(List) = null;

fn alloc(ptr: *anyopaque, len: usize, alignment: Alignment, ret_addr: usize) ?[*]u8 {
    _ = ret_addr;

    const mutex: *Mutex(List) = @ptrCast(@alignCast(ptr));

    _ = mutex.aquire();
    defer mutex.release();

    _ = len;
    _ = alignment;

    return null;
}

pub fn allocator() Allocator {
    if (singleton == null) {
        singleton = Mutex(List).init(List{});
    }

    return Allocator{
        .ptr = &singleton.?,
        .vtable = &VTable{
            .alloc = alloc,
            // not supported YET
            .free = undefined,
            .remap = undefined,
            .resize = undefined,
        },
    };
}
