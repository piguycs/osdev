pub const Lock = struct {
    name: []const u8,
    locked: u32, // we use u32 for atomic operations

    pub fn new(name: []const u8) Lock {
        return .{
            .name = name,
            .locked = 0,
        };
    }

    pub fn acquire(lock: *Lock) void {
        while (@atomicRmw(u32, &lock.locked, .Xchg, 1, .acquire) == 1) {}
    }

    pub fn release(lock: *Lock) void {
        @atomicStore(u32, &lock.locked, 0, .release);
    }
};
