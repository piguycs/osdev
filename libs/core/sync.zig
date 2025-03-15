const std = @import("std");
const riscv = @import("riscv");

const Atomic = std.atomic.Value;

const panic = @import("log.zig").panic;

pub fn Mutex(comptime T: type) type {
    return comptime struct {
        const Self = @This();

        data: T,
        lock: SpinLock,

        pub fn init(data: T) Self {
            return .{
                .data = data,
                .lock = SpinLock.new("mutex"),
            };
        }

        pub fn aquire(self: *Self) *T {
            self.lock.acquire();
            return &self.data;
        }

        pub fn release(self: *Self) void {
            self.lock.release();
        }
    };
}

pub const SpinLock = struct {
    const State = enum(u8) { unlocked = 0, locked = 1 };

    name: []const u8, // good for debugging
    state: Atomic(State),

    pub fn new(name: []const u8) SpinLock {
        return .{
            .name = name,
            .state = Atomic(State).init(.unlocked),
        };
    }

    pub fn acquire(self: *SpinLock) void {
        while (true) {
            // we set the state to .locked, while getting the previous state
            switch (self.state.swap(.locked, .acquire)) {
                // if previous state was .unlocked, we break
                .unlocked => break,
                // or else, we wait for the spinlock to be released
                // pause instruction needs the Zihintpause extension
                .locked => asm volatile ("pause"),
            }
        }
    }

    pub fn release(self: *SpinLock) void {
        self.state.store(.unlocked, .release);
    }
};
