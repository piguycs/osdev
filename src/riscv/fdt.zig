fn be32_to_cpu(value: u32) u32 {
    return @byteSwap(value);
}

// would have been nice to have zig/issues/3380
pub const Header = packed struct {
    magic: u32,
    totalsize: u32,
    off_dt_struct: u32,
    off_dt_strings: u32,
    version: u32,
    last_comp_version: u32,
    boot_cpuid_phy: u32,
    size_dt_strings: u32,
    size_dt_struct: u32,

    pub fn isValid(self: Header) bool {
        return @byteSwap(self.magic) == 0xd00dfeed;
    }
};
