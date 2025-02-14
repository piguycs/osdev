pub fn csrr(comptime reg: []const u8) u64 {
    const rett = asm volatile ("csrr %[ret], " ++ reg
        : [ret] "={a0}" (-> u32),
    );

    return rett;
}

pub fn csrw(comptime reg: []const u8, value: u64) void {
    asm volatile ("csrr %[val], " ++ reg
        :
        : [val] "{a0}" (value),
        : "{a0}"
    );
}
