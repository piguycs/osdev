const uart = @import("uart.zig");
const std = @import("std");

// Here we set up a printf-like writer from the standard library by providing
// a way to output via the UART.
const Writer = std.io.Writer(u32, error{}, uart_put_str);
const uart_writer = Writer{ .context = 0 };

fn uart_put_str(_: u32, str: []const u8) !usize {
    for (str) |ch| {
        uart.put_char(ch);
    }
    return str.len;
}

pub fn println(comptime fmt: []const u8, args: anytype) void {
    uart_writer.print(fmt ++ "\n", args) catch {};
}

export fn trap() noreturn {
    while (true) {}
}

export fn kmain() void {
    uart.init();
    println("HELLO WORLD", .{});

    while (true) {}
}
