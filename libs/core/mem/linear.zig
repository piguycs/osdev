//! Simple allocator

const sync = @import("../sync.zig");
const mem = @import("mem.zig");
const std = @import("std");

// end of the kernel code (defined in linker.ld)
extern const end: u8;

const Alignment = std.mem.Alignment;
const Allocator = std.mem.Allocator;
const VTable = std.mem.Allocator.VTable;
const Mutex = sync.Mutex;

const log = std.log.scoped(.core_mem_linear);

///how many pages to expand the freelist by
const FREELIST_EXPAND_AMT = 128;
const PAGE_SIZE = mem.PAGE_SIZE;

var singleton: ?Mutex(Freelist) = null;
const Freelist = struct {
    next: ?*Freelist,

    pub fn free(self: *Freelist, phyaddr: []u8) void {
        if (phyaddr.len != PAGE_SIZE) log.err("kfree", .{});

        // we set all invalid mem addresses to 1 and all acquired ones to 0
        @memset(phyaddr, 1);

        const kmem: *Freelist = @ptrCast(@alignCast(phyaddr.ptr));

        kmem.next = self.next;
        self.next = kmem;
    }

    pub fn expand(self: *Freelist, amount: u64) void {
        var currPage = mem.pageRoundUp(@intFromPtr(&end));
        const rangeEnd = currPage + (amount * PAGE_SIZE);

        while (currPage <= rangeEnd) : (currPage += PAGE_SIZE) {
            const phyAddr = @as([*]u8, @ptrFromInt(currPage))[0..PAGE_SIZE];
            self.free(phyAddr);
        }
    }

    pub fn nextNodeOrExpand(self: *Freelist) ?*Freelist {
        if (self.next == null) self.expand(FREELIST_EXPAND_AMT);
        return self.next;
    }
};

fn alloc(ptr: *anyopaque, len: usize, alignment: Alignment, ret_addr: usize) ?[*]u8 {
    const mutex: *Mutex(Freelist) = @ptrCast(@alignCast(ptr));
    const freelist = mutex.aquire();
    defer mutex.release();

    const pages_needed = (len + PAGE_SIZE - 1) / PAGE_SIZE;

    const first_node = freelist.nextNodeOrExpand() orelse {
        log.err("out of memory :( [ra=0x{x}]", .{ret_addr});
        return null;
    };

    const buf_ptr = @as([*]u8, @ptrCast(@alignCast(first_node)));

    freelist.next = first_node.next;

    @memset(buf_ptr[0..PAGE_SIZE], 0);

    _ = alignment;
    //const addr = @intFromPtr(buf_ptr);
    //if (!alignment.check(addr)) {
    //    log.err(
    //        "alignment check failed: addr=0x{x}, required={x}, ra=0x{x}",
    //        .{ addr, alignment, ret_addr },
    //    );

    //    freelist.free(buf_ptr[0..PAGE_SIZE]);
    //    return null;
    //}

    if (pages_needed > 1) {
        log.warn("more than one page allocated at 0x{x}", .{ret_addr});
        // we already allocated the first page, so we start from 1
        var i: usize = 1;
        _ = &i;
        log.err("TODO: not yet implimented more than 1 page allocs", .{});
        return null;
    }

    return buf_ptr;
}

fn free(ptr: *anyopaque, buf: []u8, _: Alignment, ret_addr: usize) void {
    const mutex: *Mutex(Freelist) = @ptrCast(@alignCast(ptr));
    const freelist = mutex.aquire();
    defer mutex.release();

    if (buf.len != PAGE_SIZE) {
        log.err("Cannot free non-page-sized allocation of {d} bytes [ra=0x{x}]", .{ buf.len, ret_addr });
        return;
    }

    freelist.free(buf);
}

pub fn allocator() Allocator {
    if (singleton == null) {
        singleton = Mutex(Freelist).init(Freelist{ .next = null });
    }

    return Allocator{
        .ptr = &singleton.?,
        .vtable = &VTable{
            .alloc = alloc,
            .free = free,
            // not supported
            .remap = undefined,
            // not supported
            .resize = undefined,
        },
    };
}

pub fn deinit() void {
    log.panic("TODO", .{}, @src());
}
