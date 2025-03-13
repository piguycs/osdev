const std = @import("std");
const riscv = @import("riscv");
const sync = @import("sync.zig");

const StackTrace = std.builtin.StackTrace;
const SpinLock = sync.SpinLock;
const sbi = riscv.sbi;

const Colour = struct {
    const reset = "\x1b[0m";
    const red = "\x1b[31m";
    const green = "\x1b[32m";
    const yellow = "\x1b[33m";
    const blue = "\x1b[34m";
    const magenta = "\x1b[35m";
    const cyan = "\x1b[36m";
    const white = "\x1b[37m";
};

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
    const colour = switch (level) {
        .debug => Colour.cyan,
        .info => Colour.green,
        .warn => Colour.yellow,
        .err => Colour.red,
    };

    const lvlStr = switch (level) {
        .debug => "DEBUG",
        .info => "INFO",
        .warn => "WARN",
        .err => "ERROR",
    };

    const scopeStr = @tagName(scope);
    println(colour ++ "[{s} {s}] " ++ format ++ Colour.reset, .{ lvlStr, scopeStr } ++ args);
}
