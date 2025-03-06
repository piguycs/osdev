const sbi = @import("riscv/sbi.zig");
const spinlock = @import("spinlock.zig");
const std = @import("std");
const SourceLocation = std.builtin.SourceLocation;

var panicked = false;

const Writer = std.io.GenericWriter(u32, error{}, put_str);
const sbi_writer = Writer{ .context = 0 };

fn put_str(_: u32, str: []const u8) !usize {
    _ = sbi.DebugConsoleExt.write(str);
    return str.len;
}

var writeLock: spinlock.Lock = undefined;

pub fn init() void {
    writeLock = spinlock.Lock.new("writer");
}

pub fn println(comptime fmt: []const u8, args: anytype) void {
    writeLock.acquire();
    defer writeLock.release();

    if (panicked) hang();
    sbi_writer.print(fmt ++ "\n", args) catch {};
}

pub inline fn panic(comptime fmt: []const u8, args: anytype, src: ?SourceLocation) void {
    if (panicked) hang();

    sbi_writer.print("\nPANIC: ", .{}) catch {};
    sbi_writer.print(fmt, args) catch {};

    if (src) |src_v| {
        sbi_writer.print(" [{string} {string}() {any}:{any}]\n", .{
            src_v.file,
            src_v.fn_name,
            src_v.line,
            src_v.column,
        }) catch {};
    } else {
        sbi_writer.print("\n", .{}) catch {};
    }

    hang();
}

export fn hang() noreturn {
    panicked = true;
    while (true) {}
}
