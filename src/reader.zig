const sbi = @import("riscv/sbi.zig");
const spinlock = @import("spinlock.zig");
const std = @import("std");
const SourceLocation = std.builtin.SourceLocation;

const Reader = std.io.GenericReader(u32, error{}, read_str);
const sbi_reader = Reader{ .context = 0 };

fn read_str(_: u32, str: []u8) !usize {
    const bytes_read = sbi.DebugConsoleExt.read(@intFromPtr(&str), 2048);
    return bytes_read.value;
}

var readLock: spinlock.Lock = undefined;

pub fn init() void {
    readLock = spinlock.Lock.new("reader");
}

pub fn read(str: []u8) !usize { // Artur: TODO: Add terminator for the input?
    // We should only have one reader at a time
    readLock.acquire();
    defer readLock.release();

    return sbi_reader.read(str);
}
