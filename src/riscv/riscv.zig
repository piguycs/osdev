// supervisor interrupt flags
// documentation for these values is on section 10.1 of risc-v priv isa pdf
const SIE_SEIE = 1 << 9; // external
const SIE_STIE = 1 << 5; // timer
const SIE_SSIE = 1 << 1; // software

pub inline fn csrr(comptime reg: []const u8) u64 {
    return asm volatile ("csrr %[ret], " ++ reg
        : [ret] "={a0}" (-> u64),
    );
}

pub inline fn csrw(comptime reg: []const u8, value: u64) void {
    asm volatile ("csrw " ++ reg ++ ", %[val]"
        :
        : [val] "{t0}" (value),
    );
}

///sets supervisor mode to handle external, timer and software interrupts
pub inline fn enable_all_sie() void {
    csrw("sie", SIE_SEIE | SIE_STIE | SIE_SSIE);
}

pub inline fn sfence_vma() void {
    asm volatile ("sfence.vma zero, zero");
}

pub const Satp = packed struct {
    mode: u4,
    asid: u16,
    ppn: u44,
};

pub const Mode = enum(u4) {
    Sv39 = 8,
};

pub inline fn set_satp(mode: Mode, pagetable: u64) void {
    csrw("satp", @bitCast(Satp{
        .mode = @intFromEnum(mode),
        .asid = 0,
        .ppn = @truncate(pagetable >> 12),
    }));
}
