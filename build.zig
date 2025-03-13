const std = @import("std");

pub const QEMU_OPTS = .{
    "qemu-system-riscv64", //"-nographic",
    "-machine",
    "virt",
    "-smp",
    "4",
    "-m",
    "2G",
    "-bios",
    "default",
    "-kernel",
    "zig-out/bin/kernel",
    // serial output + console gets stored in a logfile
    "-chardev",
    "stdio,id=char0,mux=on,logfile=zig-out/serial.log,signal=on",
    "-serial",
    "chardev:char0",
    "-mon",
    "chardev=char0",
    "-device",
    "bochs-display",
    "-device",
    "qemu-xhci,id=xhci,bus=pcie.0,addr=0x3",
    "-device",
    "usb-kbd,bus=xhci.0",
};

pub const QEMU_DBG = QEMU_OPTS ++ .{ "-s", "-S" };

pub fn build(b: *std.Build) !void {
    const target_conf = .{
        .cpu_arch = .riscv64,
        .abi = .none,
        .os_tag = .freestanding,
    };

    const target = b.standardTargetOptions(.{ .default_target = target_conf });
    const optimize = b.standardOptimizeOption(.{});

    const kernel = b.addExecutable(.{
        .name = "kernel",
        .root_source_file = b.path("src/kernel.zig"),
        .target = target,
        .optimize = optimize,
        .code_model = .medium,
    });

    kernel.setLinkerScriptPath(b.path("linker.ld"));
    try addAllAssemblyFiles(b, kernel); // adds all files from asm/

    b.installArtifact(kernel);

    runWithQemuCmd(b);
    objdumpCmd(b);
}

fn runWithQemuCmd(b: *std.Build) void {
    const run_cmd = b.addSystemCommand(&QEMU_OPTS);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const step = b.step("run", "Run kernel with QEMU");
    step.dependOn(&run_cmd.step);

    const run_dbg_cmd = b.addSystemCommand(&QEMU_DBG);
    run_dbg_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_dbg_cmd.addArgs(args);

    const step_dbg = b.step("run-dbg", "Run kernel with QEMU in debug mode (gdb server on :1234)");
    step_dbg.dependOn(&run_dbg_cmd.step);
}

fn objdumpCmd(b: *std.Build) void {
    const objdump_cmd = b.addSystemCommand(&.{
        "llvm-objdump",
        "-d",
        "zig-out/bin/kernel",
    });
    objdump_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| objdump_cmd.addArgs(args);

    const step = b.step("objdump", "objdump the kernel (view asm)");
    step.dependOn(&objdump_cmd.step);
}

// Add this function to scan and add all assembly files from the asm/ directory
fn addAllAssemblyFiles(b: *std.Build, kernel: *std.Build.Step.Compile) !void {
    var dir = try std.fs.cwd().openDir("asm/", .{ .iterate = true });
    defer dir.close();

    var iterator = dir.iterate();
    while (try iterator.next()) |entry| {
        if (std.mem.endsWith(u8, entry.name, ".S")) {
            const asm_path = b.fmt("asm/{s}", .{entry.name});
            kernel.addAssemblyFile(b.path(asm_path));
        }
    }
}
