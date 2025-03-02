const sbi = @import("riscv/sbi.zig");
const std = @import("std");

const SourceLocation = std.builtin.SourceLocation;

// we do not want multiple panics, as it might cause too much chaos
// we block all uart logs once a panic is hit. the default gdb config
var panicked = false;

// TODO: make use of a global spinlock here, in order to prevent race a condition
// when individual harts wish to log stuff
const Writer = std.io.GenericWriter(u32, error{}, put_str);
const sbi_writer = Writer{ .context = 0 };

fn put_str(_: u32, str: []const u8) !usize {
    _ = sbi.DebugConsoleExt.write(str);
    return str.len;
}

pub inline fn panic(comptime fmt: []const u8, args: anytype, src: ?SourceLocation) void {
    if (panicked) hang();

    sbi_writer.print("PANIC: ", .{}) catch {};
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

pub fn println(comptime fmt: []const u8, args: anytype) void {
    if (panicked) hang();

    sbi_writer.print(fmt ++ "\n", args) catch {};
}

// exporting this function so that I can easily add a breakpoint in gdb
// using lldb fixes this issue, but I dont wanna learn a new debugger ._.
// .gdbinit automatically adds a breakpoint for this function
export fn hang() noreturn {
    panicked = true;
    while (true) {}
}
