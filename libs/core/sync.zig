const std = @import("std");
const Atomic = std.atomic.Value;

pub const SpinLock = struct {
    const State = enum(u8) { unlocked = 0, locked = 1 };

    name: []const u8, // good for debugging
    state: Atomic(State),

    pub fn new(name: []const u8) SpinLock {
        return .{ .name = name, .state = Atomic(State).init(.unlocked) };
    }

    pub fn acquire(self: *SpinLock) void {
        while (true) {
            switch (self.state.swap(.locked, .acquire)) {
                .unlocked => break,
                .locked => asm volatile ("pause"),
            }
        }
    }

    pub fn release(self: *SpinLock) void {
        self.state.store(.unlocked, .release);
    }
};
