const println = @import("writer.zig").println;

extern const _mem_start: [*]const u8;
extern const _mem_end: [*]const u8;

pub const PAGE_SIZE = 4096; // bytes

pub const node = struct {
    next_ptr: ?usize = null,
};

var kmem = node{};

pub fn init() void {
    if (kmem.next_ptr != null) {
        println("WARN: avoiding double initialisation of memory", .{});
        return;
    }

    kmem.next_ptr = @intFromPtr(&_mem_start);
}

pub fn kalloc(pages: usize) ?[]u8 {
    if (pages <= 0) return null;

    const addr = kmem.next_ptr.?;
    const mem_size = pages * PAGE_SIZE;

    kmem.next_ptr.? += mem_size;

    if (kmem.next_ptr.? > @intFromPtr(&_mem_end)) {
        println("WARN: requested memory is out of bounds", .{});
        return null;
    }

    const curr_mem = @as([*]u8, @ptrFromInt(addr));

    const memory_slice = curr_mem[0..mem_size];
    @memset(memory_slice, 0);

    return memory_slice;
}
