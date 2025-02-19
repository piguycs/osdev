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

extern fn _second_start() void;

// hartid is set in a0, which is used for the first parameter of functions
export fn kmain(hartid: u64) noreturn {
    println("", .{});
    println(motd, .{});

    for (0..4) |id| {
        if (id == hartid) continue;

        const ret = sbi.HartStateManagement.hart_start(id, @intFromPtr(&_second_start));
        println("RET#{any}: {any}", .{ id, ret });
    }

    while (true) {}
}

export fn sec() noreturn {
    while (true) {
        asm volatile ("wfi");
    }
}
