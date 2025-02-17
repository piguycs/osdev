const EcallParams = struct {
    ext: u64,
    fid: u64,
    arg0: u64 = 0,
    arg1: u64 = 0,
    arg2: u64 = 0,
    arg3: u64 = 0,
    arg4: u64 = 0,
    arg5: u64 = 0,
};

fn ecall(params: EcallParams) sbiret {
    return asm volatile (
        \\ecall
        : [ret] "={a0},{a1}" (-> sbiret),
        : [a0] "{a0}" (params.arg0),
          [a1] "{a1}" (params.arg1),
          [a2] "{a2}" (params.arg2),
          [a3] "{a3}" (params.arg3),
          [a4] "{a4}" (params.arg4),
          [a5] "{a5}" (params.arg5),
          [a6] "{a6}" (params.fid),
          [a7] "{a7}" (params.ext),
    );
}

pub const BaseExt = struct {
    const eid = 0x10;
    const fid_impl_id = 0x1;
    const fid_probe_ext = 0x3;

    pub fn impl_id() sbiret {
        return ecall(.{
            .ext = eid,
            .fid = fid_impl_id,
        });
    }

    pub fn probe_ext(probe_eid: u64) sbiret {
        return ecall(.{
            .ext = eid,
            .fid = fid_probe_ext,
            .arg0 = probe_eid,
        });
    }
};

pub const DebugConsoleExt = struct {
    const eid = 0x4442434E;
    const fid_write = 0x0;
    const fid_read = 0x1;

    pub fn write(str: []const u8) sbiret {
        const strptr = @intFromPtr(str.ptr);
        return ecall(.{
            .ext = eid,
            .fid = fid_write,
            .arg0 = str.len,
            .arg1 = strptr,
        });
    }

    pub fn read(str: []const u8) sbiret {
        return ecall(.{
            .ext = eid,
            .fid = fid_read,
            .arg0 = str.len,
            .arg1 = @intFromPtr(str.ptr),
        });
    }
};

pub const HartStateManagement = struct {
    const eid = 0x48534D;
    const fid_hart_start = 0x0;
    const fid_hart_get_status = 0x2;

    pub fn hart_start(id: u64, addr: u64) sbiret {
        return ecall(.{
            .ext = eid,
            .fid = fid_hart_start,
            .arg0 = id,
            .arg1 = addr,
        });
    }

    pub fn hart_get_status(id: u64) sbiret {
        return ecall(.{
            .ext = eid,
            .fid = fid_hart_get_status,
            .arg0 = id,
        });
    }
};

pub fn support(comptime ext: type) bool {
    const ret = BaseExt.probe_ext(ext.eid);
    return ret.value == 1;
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
