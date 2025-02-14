fn ecall(
    ext: i32,
    fid: i32,
    arg0: u64,
    arg1: u64,
    arg2: u64,
    arg3: u64,
    arg4: u64,
    arg5: u64,
) sbiret {
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

pub const DebugConsoleExt = .{
    .eid = 0x4442434E,
    .write = 0x0,
};

pub fn console_write(str: []const u8) sbiret {
    return ecall(
        DebugConsoleExt.eid,
        DebugConsoleExt.write,
        str.len,
        @intFromPtr(str.ptr),
        0,
        0,
        0,
        0,
    );
}

// =========== TYPES ===========

pub const SbiError = enum(i64) {
    Success = 0,
    ErrFailed = -1,
    NotSupported = -2,
    InvalidParam = -3,
    ErrDenied = -4,
    InvalidAddress = -5,
    AlreadyAvailable = -6,
    AlreadyStarted = -7,
    AlreadyStopped = -8,
    NoShmem = -9,
    ErrInvalidState = -10,
    ErrBadRange = -11,
    ErrTimeout = -12,
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
