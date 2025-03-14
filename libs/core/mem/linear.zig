//! Simple allocator

const sync = @import("../sync.zig");
const log = @import("../log.zig");
const std = @import("std");

const Alignment = std.mem.Alignment;
const Allocator = std.mem.Allocator;
const VTable = std.mem.Allocator.VTable;

const Freelist = struct {
    next: ?*Freelist,
};

pub fn alloc(ptr: *anyopaque, len: usize, alignment: Alignment, ret_addr: usize) ?[*]u8 {
    _ = ptr;

    _ = len;
    _ = alignment;
    _ = ret_addr;
    return null;
}

pub fn allocator() Allocator {
    return Allocator{
        .ptr = &1,
        .vtable = &VTable{
            .alloc = alloc,
            .free = undefined,
            .remap = undefined,
            .resize = undefined,
        },
    };
}

pub fn init() void {
    //freelist_mtx = Mutex(Freelist).init(Freelist{ .next = null });
}

pub fn deinit() void {
    log.panic("TODO", .{}, @src());
}
