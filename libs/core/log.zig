const std = @import("std");
const riscv = @import("riscv");
const sync = @import("sync.zig");
const sbi = riscv.sbi;

const StackTrace = std.builtin.StackTrace;
const SpinLock = sync.SpinLock;
const SourceLocation = std.builtin.SourceLocation;

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
    // we get rid of the `init` function here by simply doing this
    if (lock == null) lock = SpinLock.new("log");

    lock.?.acquire();
    defer lock.?.release();

    sbi_writer.print(fmt, args) catch {};
}

pub fn println(comptime fmt: []const u8, args: anytype) void {
    print(fmt ++ "\n", args);
}

pub fn panic(comptime fmt: []const u8, args: anytype, src: ?SourceLocation) noreturn {
    print("PANIC: " ++ fmt, args);

    if (src) |src_v| {
        print(" [{string} {string}() {any}:{any}]\n", .{
            src_v.file,
            src_v.fn_name,
            src_v.line,
            src_v.column,
        });
    } else {
        print("\n", .{});
    }

    hang();
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

pub fn stdPanicAdapter(msg: []const u8, first_trace_addr: ?usize) noreturn {
    if (msg.len > 0) println("panic message: {s}", .{msg});

    var addr = first_trace_addr orelse unreachable;
    var fp = asm volatile (
        \\nop
        : [ret] "={fp}" (-> u64),
    );

    var depth: u64 = 0;
    const max_depth = 10;

    while (depth < max_depth) : (depth += 1) {
        println("STACK TRACE:", .{});
        println("{d:4}: 0x{x} fp: 0x{x}", .{ depth, addr, fp });
        addr = @as(*u64, @ptrFromInt(fp - 8)).*;
        fp = @as(*u64, @ptrFromInt(fp - 16)).*;
    }

    println("==== END OF STACK TRACE ====", .{});

    asm volatile ("j .");
    unreachable;
}

fn isValidAddress(_: usize) bool {
    return true;
}

export fn hang() noreturn {
    while (true) {}
}
