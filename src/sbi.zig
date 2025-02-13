pub fn ecall(ext: i32, fid: i32, arg0: u64, arg1: u64, arg2: u64, arg3: u64, arg4: u64, arg5: u64) sbiret {
    return asm volatile (
        \\ecall
        : [ret] "={a0},{a1}" (-> sbiret),
        : [a0] "{a0}" (arg0),
          [a1] "{a1}" (arg1),
          [a2] "{a2}" (arg2),
          [a3] "{a3}" (arg3),
          [a4] "{a4}" (arg4),
          [a5] "{a5}" (arg5),
          [a6] "{a6}" (fid),
          [a7] "{a7}" (ext),
    );
}

pub fn csrr(comptime reg: []const u8) u32 {
    const rett = asm volatile ("csrr %[ret], " ++ reg
        : [ret] "={a0}" (-> u32),
    );

    return rett;
}

// =========== TYPES ===========

pub const SbiError = enum(i64) {
    /// Completed successfully
    Success = 0,
    /// Failed
    ErrFailed = -1,
    /// Not supported
    NotSupported = -2,
    /// Invalid parameter(s)
    InvalidParam = -3,
    /// Denied or not allowed
    ErrDenied = -4,
    /// Invalid address(s)
    InvalidAddress = -5,
    /// Already available
    AlreadyAvailable = -6,
    /// Already started
    AlreadyStarted = -7,
    /// Already stopped
    AlreadyStopped = -8,
    /// Shared memory not available
    NoShmem = -9,
    /// Invalid state
    ErrInvalidState = -10,
    /// Bad (or invalid) range
    ErrBadRange = -11,
    /// Failed due to timeout
    ErrTimeout = -12,
    /// Input/Output error
    ErrIo = -13,
};

pub const sbiret = packed struct {
    errno: SbiError,
    value: u64,

    pub fn toString(self: sbiret) []const u8 {
        const str = switch (self.errno) {
            .Success => "Completed successfully",
            .ErrFailed => "Failed",
            .NotSupported => "Not supported",
            .InvalidParam => "Invalid parameter(s)",
            .ErrDenied => "Denied or not allowed",
            .InvalidAddress => "Invalid address(s)",
            .AlreadyAvailable => "Already available",
            .AlreadyStarted => "Already started",
            .AlreadyStopped => "Already stopped",
            .NoShmem => "Shared memory not available",
            .ErrInvalidState => "Invalid state",
            .ErrBadRange => "Bad (or invalid) range",
            .ErrTimeout => "Failed due to timeout",
            .ErrIo => "Input/Output error",
        };

        return str;
    }
};
