const writer = @import("writer.zig");
const riscv = @import("../riscv/riscv.zig");
const std = @import("std");

// Log levels in order of increasing severity
pub const LogLevel = enum {
    debug,
    info,
    warn,
    err,
    critical,

    pub fn getColor(self: LogLevel) []const u8 {
        return switch (self) {
            .debug => "\x1b[90m", // Dark gray
            .info => "\x1b[32m", // Green
            .warn => "\x1b[33m", // Yellow
            .err => "\x1b[31m", // Red
            .critical => "\x1b[35m", // Magenta
        };
    }

    pub fn toString(self: LogLevel) []const u8 {
        return switch (self) {
            .debug => "DEBUG",
            .info => "INFO",
            .warn => "WARN",
            .err => "ERROR",
            .critical => "CRIT",
        };
    }
};

// Global start time for relative timestamps
var start_time: u64 = undefined;

// Initialize the logger with the current system time
pub fn init() void {
    start_time = riscv.csrr("time");
}

// Get current timestamp in milliseconds since start
fn getTimestamp() u64 {
    const current_time = riscv.csrr("time");
    const elapsed = current_time - start_time;
    // Convert from CPU ticks to milliseconds (assuming 10MHz clock for QEMU RISC-V)
    return elapsed / 10000;
}

// Main logging function
pub fn log(
    level: LogLevel,
    comptime fmt: []const u8,
    args: anytype,
    src: std.builtin.SourceLocation,
) void {
    const timestamp = getTimestamp();
    const reset_color = "\x1b[0m";
    const level_color = level.getColor();

    // Format: [TIME][LEVEL][FILE:LINE] Message
    writer.print("[{d:0>5}][{s}{s}{s}][{s}:{d}] ", .{
        timestamp,
        level_color,
        level.toString(),
        reset_color,
        src.file,
        src.line,
    });
    writer.print(fmt ++ "\n", args);
}

// Convenience functions for different log levels
pub fn debug(comptime fmt: []const u8, args: anytype, src: std.builtin.SourceLocation) void {
    log(.debug, fmt, args, src);
}

pub fn info(comptime fmt: []const u8, args: anytype, src: std.builtin.SourceLocation) void {
    log(.info, fmt, args, src);
}

pub fn warn(comptime fmt: []const u8, args: anytype, src: std.builtin.SourceLocation) void {
    log(.warn, fmt, args, src);
}

pub fn err(comptime fmt: []const u8, args: anytype, src: std.builtin.SourceLocation) void {
    log(.err, fmt, args, src);
}

pub fn critical(comptime fmt: []const u8, args: anytype, src: std.builtin.SourceLocation) void {
    log(.critical, fmt, args, src);
}

// Macros to automatically include source location
pub fn DEBUG(comptime fmt: []const u8, args: anytype) void {
    debug(fmt, args, @src());
}

pub fn INFO(comptime fmt: []const u8, args: anytype) void {
    info(fmt, args, @src());
}

pub fn WARN(comptime fmt: []const u8, args: anytype) void {
    warn(fmt, args, @src());
}

pub fn ERROR(comptime fmt: []const u8, args: anytype) void {
    err(fmt, args, @src());
}

pub fn CRITICAL(comptime fmt: []const u8, args: anytype) void {
    critical(fmt, args, @src());
}
