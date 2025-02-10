const println = @import("writer.zig").println;

const motd =
    \\
    \\Welcome to $(cat name.txt)
;

extern var _bss: [0]u8;
extern var _bss_end: [0]u8;
extern var _stack: [0]u8;

pub fn memset(buf: [*]u8, c: u8, n: usize) [*]u8 {
    var p: [*]u8 = buf;
    for (0..n) |i| {
        p[i] = c;
    }
    return buf;
}

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

    const bss_start = @intFromPtr(&_bss);
    const bss_end = @intFromPtr(&_bss_end);
    const bss_size: usize = @intCast(bss_end - bss_start);

    _ = memset(&_bss, 0, bss_size);

    asm volatile ("unimp");
    while (true) {}
}
