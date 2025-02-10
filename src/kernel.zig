const println = @import("writer.zig").println;

const motd =
    \\
    \\Welcome to $(cat name.txt)
;

export fn handle_trap() noreturn {
    const scause = asm volatile (
        \\csrr a0, scause
        : [a0] "={a0}" (-> u32),
    );

    const stval = asm volatile (
        \\csrr a0, stval
        : [a0] "={a0}" (-> u32),
    );

    const sepc = asm volatile (
        \\csrr a0, sepc
        : [a0] "={a0}" (-> u32),
    );

    println("PANIC scause={?} stval={?} sepc={?}", .{ scause, stval, sepc });

    while (true) {}
}

export fn kmain() noreturn {
    println(motd, .{});

    asm volatile ("unimp");
    while (true) {}
}
