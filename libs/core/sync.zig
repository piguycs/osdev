pub const SpinLock = struct {
    name: []const u8, // good for debugging
    locked: bool,

    pub fn new(name: []const u8) SpinLock {
        return .{ .name = name, .locked = false };
    }

    pub fn acquire(lock: *SpinLock) void {
        while (@atomicRmw(bool, &lock.locked, .Xchg, true, .acquire) == true) {
            asm volatile ("pause");
        }
    }

    pub fn release(lock: *SpinLock) void {
        @atomicStore(bool, &lock.locked, false, .release);
    }
};
