const sbi = @import("sbi.zig");
const std = @import("std");

const Writer = std.io.Writer(u32, error{}, put_str);
const sbi_writer = Writer{ .context = 0 };

fn put_str(_: u32, str: []const u8) !usize {
    for (str) |c| {
        sbi.print_char(c);
    }

    return str.len;
}

pub fn println(comptime fmt: []const u8, args: anytype) void {
    sbi_writer.print(fmt ++ "\n", args) catch {};
}
