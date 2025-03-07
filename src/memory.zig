const sync = @import("spinlock.zig");
const writer = @import("writer.zig");

const println = writer.println;

const PAGE_SIZE = 4096;

pub const MemTree = struct {
    next: ?*MemTree,
};

///# linear allocator
///allocates contigous chunks of memory
///this CAN and WILL result in fragmentation
pub const KAlloc = struct {
    mem: MemTree,
    lock: sync.Lock,

    pub fn init(comptime size: comptime_int) KAlloc {
        _ = size;
        return .{
            .mem = MemTree{ .next = null },
            .lock = sync.Lock.new("kmem"),
        };
    }
};
