const std = @import("std");
const riscv = @import("riscv");
const sync = @import("sync.zig");

const StackTrace = std.builtin.StackTrace;
const SpinLock = sync.SpinLock;
const sbi = riscv.sbi;

var lock: ?SpinLock = null;

const Writer = std.io.GenericWriter(void, error{}, put_str);
const sbi_writer = Writer{ .context = undefined };

fn put_str(_: void, str: []const u8) !usize {
    _ = sbi.DebugConsoleExt.write(str);
    return str.len;
}

pub fn print(comptime fmt: []const u8, args: anytype) void {
    if (lock == null) lock = SpinLock.new("log");
    lock.?.acquire();
    defer lock.?.release();
    sbi_writer.print(fmt, args) catch {};
}

pub fn println(comptime fmt: []const u8, args: anytype) void {
    print(fmt ++ "\n", args);
}

pub fn stdLogAdapter(
    comptime level: std.log.Level,
    comptime scope: @Type(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    const lvlStr = switch (level) {
        .debug => "DEBUG",
        .info => "INFO",
        .warn => "WARN",
        .err => "ERROR",
    };

    const scopeStr = @tagName(scope);
    println("[{s} {s}] " ++ format, .{ lvlStr, scopeStr } ++ args);
}
