const println = @import("writer.zig").println;
const riscv = @import("riscv/riscv.zig");
const sbi = @import("riscv/sbi.zig");

const motd = "Welcome to $(cat name.txt)";

export fn trap() noreturn {
    const scause = riscv.csrr("scause");
    const svalue = riscv.csrr("stval");
    const sepc = riscv.csrr("sepc");

    println("exception: scause={x} svalue={x} sepc={x}", .{ scause, svalue, sepc });
    println("(TIP) run: llvm-addr2line -e zig-out/bin/kernel {x}", .{sepc});

    while (true) {}
}

// hartid is set in a0, which is used for the first parameter of functions
export fn kmain(hartid: u64) noreturn {
    println("", .{});
    println(motd, .{});

    for (0..4) |id| {
        if (id != hartid - 1) {
            const ret = sbi.HartStateManagement.hart_start(id, null);
            println("RET#{any}: {any}", .{ id, ret });
        }
    }

    while (true) {}
}

export fn secondary(_: u64) noreturn {
    while (true) {}
}
