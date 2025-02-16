const println = @import("writer.zig").println;
const sbi = @import("sbi.zig");
const riscv = @import("riscv.zig");
const mem = @import("mem.zig");

const motd = "Welcome to $(cat name.txt)";

export fn trap() noreturn {
    const scause = riscv.csrr("scause");
    const svalue = riscv.csrr("stval");
    const sepc = riscv.csrr("sepc");

    println("exception: scause={x} svalue={x} sepc={x}", .{ scause, svalue, sepc });
    println("(TIP) run: llvm-addr2line -e zig-out/bin/kernel {x}", .{sepc});

    while (true) {}
}

export fn kmain() noreturn {
    println("", .{});
    println(motd, .{});

    // init stuff
    mem.init();

    const page = mem.kalloc(1).?;

    _ = page;

    while (true) {}
}
