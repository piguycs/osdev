const std = @import("std");
const riscv = @import("riscv");
const core = @import("core");

const sbi = riscv.sbi;

const SourceLocation = std.builtin.SourceLocation;
const SpinLock = core.sync.SpinLock;

const Reader = std.io.GenericReader(u32, error{}, read_str);
const sbi_reader = Reader{ .context = 0 };

fn read_str(_: u32, str: []u8) !usize {
    const bytes_read = sbi.DebugConsoleExt.read(@intFromPtr(&str), 2048);
    return bytes_read.value;
}

var readLock: SpinLock = undefined;

pub fn init() void {
    readLock = SpinLock.new("reader");
}

// Artur: TODO: Add terminator for the input
pub fn read(str: []u8) !usize {
    // We should only have one reader at a time
    readLock.acquire();
    defer readLock.release();

    return sbi_reader.read(str);
}
