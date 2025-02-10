const sbiret = packed struct {
    errno: u32,
    value: u32,
};

const Opcode = enum(u8) {
    Write = 1,
};

pub fn print_char(char: u8) void {
    _ = asm volatile (
        \\ ecall
        : [ret_a0] "={a0},{a1}" (-> struct { u32, u32 }),
        : [a0] "{a0}" (char),
          [a7] "{a7}" (Opcode.Write),
        : "memory"
    );
}
