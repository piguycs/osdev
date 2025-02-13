const println = @import("writer.zig").println;
const std = @import("std");
const sbi = @import("sbi.zig");

const motd = "Welcome to $(cat name.txt)";

export fn trap() noreturn {
    const scause = sbi.csrr("scause");
    const svalue = sbi.csrr("stval");
    const sepc = sbi.csrr("sepc");

    println("trap card activated scause={x} svalue={x} sepc={x}", .{ scause, svalue, sepc });

    while (true) {}
}

export fn kmain() noreturn {
    println("", .{});
    println(motd, .{});

    asm volatile ("unimp");

    while (true) {}
}
