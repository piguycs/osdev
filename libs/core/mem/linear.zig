//! Simple allocator

const sync = @import("../sync.zig");
const mem = @import("mem.zig");
const std = @import("std");

// end of the kernel code (defined in linker.ld)
extern const end: void;

const Alignment = std.mem.Alignment;
const Allocator = std.mem.Allocator;
const VTable = std.mem.Allocator.VTable;
const Mutex = sync.Mutex;

const log = std.log.scoped(.core_mem_linear);

///how many pages to expand the freelist by
const FREELIST_EXPAND_AMT = 128;

var singleton: Mutex(Freelist) = undefined;
const Freelist = struct {
    next: ?*Freelist,

    pub fn expand(self: *Freelist, amount: u64) void {
        const memStart = pageRoundUp(@intFromPtr(&end));
        _ = memStart;

        _ = self;
        for (0..amount) |_| {
            //
        }
    }

    pub fn nextNodeOrExpand(self: *Freelist) ?*Freelist {
        return self.next;
    }
};

fn alloc(ptr: *anyopaque, len: usize, alignment: Alignment, ret_addr: usize) ?[*]u8 {
    const mutex: *Mutex(Freelist) = @ptrCast(@alignCast(ptr));
    const freelist = mutex.aquire();
    defer mutex.release();

    const node = freelist.nextNodeOrExpand() orelse {
        log.err("out of memory :( [ra=0x{x}]", .{ret_addr});
        return null;
    };

    _ = node;
    _ = len;
    _ = alignment;

    return null;
}

pub fn allocator() Allocator {
    return Allocator{
        .ptr = &singleton,
        .vtable = &VTable{
            // W.I.P.
            .alloc = alloc,
            // not supported YET
            .free = undefined,
            // not supported
            .remap = undefined,
            // not supported
            .resize = undefined,
        },
    };
}

pub fn init() void {
    singleton = Mutex(Freelist).init(Freelist{ .next = null });
}

pub fn deinit() void {
    log.panic("TODO", .{}, @src());
}

pub fn pageRoundUp(input: u64) u64 {
    const PAGE_SIZE = mem.PAGE_SIZE;
    comptime if ((PAGE_SIZE & (PAGE_SIZE - 1)) != 0) {
        @compileError("PAGE_SIZE must be a power of 2");
    };

    const mask: u64 = PAGE_SIZE - 1;
    return (input + mask) & ~(mask);
}
