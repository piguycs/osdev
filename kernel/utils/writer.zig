//! SOON TO BE DEPRACATED: use std.log and @import("core").log then

const std = @import("std");
const sbi = @import("../riscv/sbi.zig");
const core = @import("core");

const SourceLocation = std.builtin.SourceLocation;
const SpinLock = core.sync.SpinLock;

export var panicked = false;

const Writer = std.io.GenericWriter(u32, error{}, put_str);
const WriterChar = std.io.GenericWriter(u32, error{}, put_char);

const sbi_writer = Writer{ .context = 0 };
const sbi_writer_char = WriterChar{ .context = 0 };

fn put_str(_: u32, str: []const u8) !usize {
    _ = sbi.DebugConsoleExt.write(str);
    return str.len;
}

fn put_char(_: u32, char: []const u8) !usize {
    _ = sbi.DebugConsoleExt.write(char);
    return 1;
}

var writeLock: SpinLock = undefined;

pub fn init() void {
    writeLock = SpinLock.new("writer");
}

pub fn print(comptime fmt: []const u8, args: anytype) void {
    writeLock.acquire();
    defer writeLock.release();

    if (panicked) hang();
    sbi_writer.print(fmt, args) catch {};
}

pub fn println(comptime fmt: []const u8, args: anytype) void {
    print(fmt ++ "\n", args);
}

pub fn printchar(char: u8) void {
    writeLock.acquire();
    defer writeLock.release();

    if (panicked) hang();
    var v = [_]u8{char};
    _ = put_char(0, &v) catch {};
}

pub fn panic(comptime fmt: []const u8, args: anytype, src: ?SourceLocation) noreturn {
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

pub fn assert(ok: bool, comptime fmt: ?[]const u8, src: ?SourceLocation) void {
    if (ok) panic(fmt, .{}, src);
}

///comptime assert
pub fn ct_assert(ok: bool, comptime fmt: ?[]const u8) void {
    if (ok) @compileError(fmt orelse "assert failed");
}

export fn hang() noreturn {
    panicked = true;
    while (true) {}
}
