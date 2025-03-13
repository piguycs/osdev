///DEPRACATED: use @import("core").sync.Spinlock
pub const Lock = struct {
    name: []const u8,
    locked: bool, // we use u32 for atomic operations

    pub fn new(name: []const u8) Lock {
        return .{
            .name = name,
            .locked = false,
        };
    }

    pub fn acquire(lock: *Lock) void {
        while (@atomicRmw(bool, &lock.locked, .Xchg, true, .acquire) == true) {}
    }

    pub fn release(lock: *Lock) void {
        @atomicStore(bool, &lock.locked, false, .release);
    }
};
