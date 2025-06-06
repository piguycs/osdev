const core = @import("core");

const SpinLock = core.sync.SpinLock;

// end of the kernel code (defined in linker.ld)
extern const end: u8;

const panic = core.log.panic;

const PAGE_SIZE = 4096;
// HACK: I am hardcoding these in for now
const MEM_SIZE = 64 * 1024 * 1024; // 64M
const MEM_END = 0x80200000 + MEM_SIZE;

pub const FreeList = struct {
    next: ?*FreeList,
};

/// # linear allocator
/// allocates contigous chunks of memory
/// - allocates entire 4k pages n number of times
/// - this CAN result in fragmentation
pub const KAlloc = struct {
    freelist: FreeList,
    lock: SpinLock,

    pub fn init() KAlloc {
        var kmem = KAlloc{
            .freelist = FreeList{ .next = null },
            .lock = SpinLock.new("kmem"),
        };

        kmem.freeRange(@intFromPtr(&end), MEM_END);

        return kmem;
    }

    fn freeRange(self: *KAlloc, memstart: u64, memend: u64) void {
        var currPage = pageRoundUp(memstart);
        const rangeEnd: usize = @truncate(memend - PAGE_SIZE);

        while (currPage <= rangeEnd) : (currPage += PAGE_SIZE) {
            self.kfree(@as([*]u8, @ptrFromInt(currPage))[0..PAGE_SIZE]);
        }
    }

    pub fn kfree(self: *KAlloc, phyaddr: []u8) void {
        if (phyaddr.len != PAGE_SIZE) panic("kfree", .{}, @src());

        // we set all invalid mem addresses to 1 and all acquired ones to 0
        @memset(phyaddr, 1);

        const kmem: *FreeList = @ptrCast(@alignCast(phyaddr.ptr));

        self.lock.acquire();
        defer self.lock.release();

        kmem.next = self.freelist.next;
        self.freelist.next = kmem;
    }

    pub fn alloc(self: *KAlloc) []u8 {
        return self.allocT(u8);
    }

    pub fn allocT(self: *KAlloc, comptime T: type) []T {
        self.lock.acquire();
        defer self.lock.release();

        const r = self.freelist.next;

        if (r) |node| {
            self.freelist.next = node.next;

            const items_count = PAGE_SIZE / @sizeOf(T);
            const ptr = @as([*]T, @ptrCast(@alignCast(node)));
            const slice = ptr[0..items_count];

            @memset(@as([*]u8, @ptrCast(ptr))[0..PAGE_SIZE], 0);

            return slice;
        }

        panic("out of memory", .{}, @src());
    }
};

pub fn pageRoundUp(input: u64) u64 {
    comptime if ((PAGE_SIZE & (PAGE_SIZE - 1)) != 0) {
        @compileError("PAGE_SIZE must be a power of 2");
    };

    const mask: u64 = PAGE_SIZE - 1;
    return (input + mask) & ~(mask);
}
